package com.bot.grpc.server;

import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

// Connection interface for pooled connections
interface PooledConnection {
    boolean isHealthy();
    void close();
    void markAsUsed();
    long getLastUsedTime();
    String getConnectionId();
    String getTargetService();
}

// Main connection pool class
public class ConnectionPool<T extends PooledConnection> {
    private static final Logger logger = LoggerFactory.getLogger(ConnectionPool.class);
    
    private final BlockingQueue<T> availableConnections;
    private final List<T> allConnections;
    private final AtomicInteger activeConnections;
    private final ConnectionFactory<T> connectionFactory;
    private final int maxSize;
    private final int minSize;
    private final long connectionTimeout;
    private final long healthCheckInterval;
    private final ScheduledExecutorService healthCheckExecutor;
    private final Semaphore connectionSemaphore;
    private final String targetService;
    
    // Метрики пула
    private final AtomicInteger totalConnectionsCreated = new AtomicInteger(0);
    private final AtomicInteger totalConnectionsDestroyed = new AtomicInteger(0);
    private final AtomicInteger totalBorrowSuccess = new AtomicInteger(0);
    private final AtomicInteger totalBorrowFail = new AtomicInteger(0);
    private final ConcurrentHashMap<String, AtomicInteger> serviceErrors = new ConcurrentHashMap<>();
    
    private volatile boolean isShuttingDown = false;
    
    // Connection factory interface
    public interface ConnectionFactory<T> {
        T create() throws Exception;
        boolean validate(T connection);
        void destroy(T connection);
    }
    
    // Configuration builder
    public static class PoolConfig {
        private int maxSize = 20;
        private int minSize = 5;
        private long connectionTimeout = 30000;
        private long healthCheckInterval = 60000;
        private long maxConnectionLifetime = 3600000;
        private String targetService = "unknown";
        
        public PoolConfig maxSize(int maxSize) {
            this.maxSize = maxSize;
            return this;
        }
        
        public PoolConfig minSize(int minSize) {
            this.minSize = minSize;
            return this;
        }
        
        public PoolConfig connectionTimeout(long connectionTimeout) {
            this.connectionTimeout = connectionTimeout;
            return this;
        }
        
        public PoolConfig healthCheckInterval(long healthCheckInterval) {
            this.healthCheckInterval = healthCheckInterval;
            return this;
        }
        
        public PoolConfig maxConnectionLifetime(long maxConnectionLifetime) {
            this.maxConnectionLifetime = maxConnectionLifetime;
            return this;
        }
        
        public PoolConfig targetService(String targetService) {
            this.targetService = targetService;
            return this;
        }
    }
    
    public ConnectionPool(ConnectionFactory<T> connectionFactory, PoolConfig config) {
        this.connectionFactory = connectionFactory;
        this.maxSize = config.maxSize;
        this.minSize = config.minSize;
        this.connectionTimeout = config.connectionTimeout;
        this.healthCheckInterval = config.healthCheckInterval;
        this.targetService = config.targetService;
        
        this.availableConnections = new LinkedBlockingQueue<>();
        this.allConnections = new CopyOnWriteArrayList<>();
        this.activeConnections = new AtomicInteger(0);
        this.connectionSemaphore = new Semaphore(maxSize);
        this.healthCheckExecutor = Executors.newSingleThreadScheduledExecutor();
        
        initializePool();
        startHealthCheck();
        
        // Регистрируем сервис в protocol
        protocol.updateServiceHealth(targetService, true, "Pool initialized");
    }
    
    private void initializePool() {
        logger.info("Initializing connection pool for {} with min size: {}", targetService, minSize);
        
        for (int i = 0; i < minSize; i++) {
            try {
                T connection = connectionFactory.create();
                allConnections.add(connection);
                availableConnections.offer(connection);
                totalConnectionsCreated.incrementAndGet();
                logger.debug("Created initial connection {}", connection.getConnectionId());
            } catch (Exception e) {
                logger.error("Failed to create initial connection", e);
                recordServiceError("init", e.getMessage());
            }
        }
        
        // Обновляем статус в protocol
        boolean healthy = availableConnections.size() > 0;
        protocol.updateServiceHealth(targetService, healthy, 
            healthy ? "Pool ready" : "Pool initialization failed");
    }
    
    private void startHealthCheck() {
        healthCheckExecutor.scheduleAtFixedRate(() -> {
            if (!isShuttingDown) {
                long startTime = System.currentTimeMillis();
                performHealthCheck();
                long duration = System.currentTimeMillis() - startTime;
                protocol.recordServiceCall(targetService, "health_check", true, duration, null);
            }
        }, healthCheckInterval, healthCheckInterval, TimeUnit.MILLISECONDS);
    }
    
    private void performHealthCheck() {
        logger.debug("Performing health check on {} connections for {}", allConnections.size(), targetService);
        
        List<T> unhealthyConnections = new ArrayList<>();
        int healthyCount = 0;
        
        for (T connection : allConnections) {
            try {
                if (!connectionFactory.validate(connection)) {
                    logger.warn("Connection {} is unhealthy", connection.getConnectionId());
                    unhealthyConnections.add(connection);
                } else {
                    healthyCount++;
                }
            } catch (Exception e) {
                logger.error("Error during health check for connection {}", connection.getConnectionId(), e);
                unhealthyConnections.add(connection);
            }
        }
        
        // Remove unhealthy connections
        for (T connection : unhealthyConnections) {
            allConnections.remove(connection);
            availableConnections.remove(connection);
            connectionFactory.destroy(connection);
            totalConnectionsDestroyed.incrementAndGet();
            recordServiceError("health_check", "Connection unhealthy: " + connection.getConnectionId());
            logger.info("Removed unhealthy connection {}", connection.getConnectionId());
        }
        
        // Replenish pool to min size
        int currentSize = allConnections.size();
        if (currentSize < minSize) {
            int needed = minSize - currentSize;
            logger.info("Replenishing pool with {} connections for {}", needed, targetService);
            
            for (int i = 0; i < needed; i++) {
                try {
                    T connection = connectionFactory.create();
                    allConnections.add(connection);
                    availableConnections.offer(connection);
                    totalConnectionsCreated.incrementAndGet();
                } catch (Exception e) {
                    logger.error("Failed to create replacement connection", e);
                    recordServiceError("replenish", e.getMessage());
                }
            }
        }
        
        // Обновляем статус здоровья сервиса
        boolean isHealthy = healthyCount > 0 || availableConnections.size() > 0;
        protocol.updateServiceHealth(targetService, isHealthy, isHealthy ? "OK" : "No healthy connections");
    }
    
    public T borrowConnection() throws InterruptedException, TimeoutException {
        if (isShuttingDown) {
            throw new IllegalStateException("Connection pool is shutting down");
        }
        
        long startTime = System.currentTimeMillis();
        
        if (!connectionSemaphore.tryAcquire(connectionTimeout, TimeUnit.MILLISECONDS)) {
            totalBorrowFail.incrementAndGet();
            protocol.recordServiceCall(targetService, "borrow", false, 
                System.currentTimeMillis() - startTime, "Timeout");
            throw new TimeoutException("Could not acquire connection within timeout for " + targetService);
        }
        
        try {
            T connection = availableConnections.poll(connectionTimeout, TimeUnit.MILLISECONDS);
            
            if (connection == null) {
                if (activeConnections.get() < maxSize) {
                    try {
                        connection = connectionFactory.create();
                        allConnections.add(connection);
                        totalConnectionsCreated.incrementAndGet();
                        logger.debug("Created new connection on demand: {}", connection.getConnectionId());
                    } catch (Exception e) {
                        connectionSemaphore.release();
                        totalBorrowFail.incrementAndGet();
                        recordServiceError("borrow", e.getMessage());
                        protocol.recordServiceCall(targetService, "borrow", false, 
                            System.currentTimeMillis() - startTime, e.getMessage());
                        throw new RuntimeException("Failed to create new connection", e);
                    }
                } else {
                    connectionSemaphore.release();
                    totalBorrowFail.incrementAndGet();
                    protocol.recordServiceCall(targetService, "borrow", false, 
                        System.currentTimeMillis() - startTime, "Max size reached");
                    throw new TimeoutException("No available connections and max size reached for " + targetService);
                }
            }
            
            activeConnections.incrementAndGet();
            connection.markAsUsed();
            totalBorrowSuccess.incrementAndGet();
            
            long duration = System.currentTimeMillis() - startTime;
            protocol.recordServiceCall(targetService, "borrow", true, duration, null);
            
            logger.debug("Borrowed connection {}. Active: {}, Available: {}", 
                connection.getConnectionId(), 
                activeConnections.get(), 
                availableConnections.size());
            
            return connection;
            
        } catch (InterruptedException e) {
            connectionSemaphore.release();
            Thread.currentThread().interrupt();
            throw e;
        }
    }
    
    public void returnConnection(T connection) {
        if (connection == null) {
            return;
        }
        
        if (isShuttingDown) {
            closeConnection(connection);
            return;
        }
        
        try {
            if (connectionFactory.validate(connection)) {
                availableConnections.offer(connection);
                logger.debug("Returned connection {}", connection.getConnectionId());
            } else {
                logger.warn("Returned connection {} is unhealthy, closing", connection.getConnectionId());
                recordServiceError("return", "Unhealthy connection returned");
                closeConnection(connection);
            }
        } catch (Exception e) {
            logger.error("Error validating returned connection", e);
            recordServiceError("return", e.getMessage());
            closeConnection(connection);
        } finally {
            activeConnections.decrementAndGet();
            connectionSemaphore.release();
        }
    }
    
    private void closeConnection(T connection) {
        allConnections.remove(connection);
        connectionFactory.destroy(connection);
        totalConnectionsDestroyed.incrementAndGet();
        logger.info("Closed connection {}", connection.getConnectionId());
    }
    
    private void recordServiceError(String operation, String error) {
        String key = targetService + "." + operation;
        serviceErrors.computeIfAbsent(key, k -> new AtomicInteger(0)).incrementAndGet();
        protocol.recordError(protocol.ErrorCode.SERVICE_UNAVAILABLE);
    }
    
    public void shutdown() {
        logger.info("Shutting down connection pool for {}", targetService);
        isShuttingDown = true;
        
        protocol.updateServiceHealth(targetService, false, "Pool shutting down");
        
        healthCheckExecutor.shutdown();
        try {
            healthCheckExecutor.awaitTermination(5, TimeUnit.SECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        
        for (T connection : allConnections) {
            try {
                connectionFactory.destroy(connection);
            } catch (Exception e) {
                logger.error("Error closing connection {}", connection.getConnectionId(), e);
            }
        }
        
        allConnections.clear();
        availableConnections.clear();
        
        logger.info("Connection pool shutdown complete for {}", targetService);
    }
    
    public int getActiveConnections() {
        return activeConnections.get();
    }
    
    public int getAvailableConnections() {
        return availableConnections.size();
    }
    
    public int getTotalConnections() {
        return allConnections.size();
    }
    
    public PoolStats getStats() {
        return new PoolStats(
            getTotalConnections(),
            getActiveConnections(),
            getAvailableConnections(),
            maxSize,
            minSize,
            totalConnectionsCreated.get(),
            totalConnectionsDestroyed.get(),
            totalBorrowSuccess.get(),
            totalBorrowFail.get()
        );
    }
    
    public static class PoolStats {
        private final int totalConnections;
        private final int activeConnections;
        private final int availableConnections;
        private final int maxSize;
        private final int minSize;
        private final int created;
        private final int destroyed;
        private final int borrowSuccess;
        private final int borrowFail;
        
        public PoolStats(int total, int active, int available, int max, int min,
                        int created, int destroyed, int borrowSuccess, int borrowFail) {
            this.totalConnections = total;
            this.activeConnections = active;
            this.availableConnections = available;
            this.maxSize = max;
            this.minSize = min;
            this.created = created;
            this.destroyed = destroyed;
            this.borrowSuccess = borrowSuccess;
            this.borrowFail = borrowFail;
        }
        
        public int getTotalConnections() { return totalConnections; }
        public int getActiveConnections() { return activeConnections; }
        public int getAvailableConnections() { return availableConnections; }
        public int getMaxSize() { return maxSize; }
        public int getMinSize() { return minSize; }
        public int getCreated() { return created; }
        public int getDestroyed() { return destroyed; }
        public int getBorrowSuccess() { return borrowSuccess; }
        public int getBorrowFail() { return borrowFail; }
        public double getSuccessRate() {
            int total = borrowSuccess + borrowFail;
            return total > 0 ? (borrowSuccess * 100.0 / total) : 100;
        }
    }
}

// GrpcConnection implementation with target service
class GrpcConnection implements PooledConnection {
    private final String connectionId;
    private final io.grpc.ManagedChannel channel;
    private final String targetService;
    private long lastUsedTime;
    private volatile boolean healthy = true;
    
    public GrpcConnection(String connectionId, io.grpc.ManagedChannel channel, String targetService) {
        this.connectionId = connectionId;
        this.channel = channel;
        this.targetService = targetService;
        this.lastUsedTime = System.currentTimeMillis();
    }
    
    public io.grpc.ManagedChannel getChannel() {
        return channel;
    }
    
    @Override
    public boolean isHealthy() {
        return healthy && !channel.isShutdown() && !channel.isTerminated();
    }
    
    @Override
    public void close() {
        channel.shutdown();
    }
    
    @Override
    public void markAsUsed() {
        this.lastUsedTime = System.currentTimeMillis();
    }
    
    @Override
    public long getLastUsedTime() {
        return lastUsedTime;
    }
    
    @Override
    public String getConnectionId() {
        return connectionId;
    }
    
    @Override
    public String getTargetService() {
        return targetService;
    }
}

// Factory implementation for gRPC connections
class GrpcConnectionFactory implements ConnectionPool.ConnectionFactory<GrpcConnection> {
    private final String targetHost;
    private final int targetPort;
    private final String targetService;
    private final AtomicInteger connectionCounter = new AtomicInteger(0);
    
    public GrpcConnectionFactory(String host, int port, String targetService) {
        this.targetHost = host;
        this.targetPort = port;
        this.targetService = targetService;
    }
    
    @Override
    public GrpcConnection create() throws Exception {
        io.grpc.ManagedChannel channel = io.grpc.netty.NettyChannelBuilder
            .forAddress(targetHost, targetPort)
            .usePlaintext()
            .maxInboundMessageSize(10 * 1024 * 1024)
            .keepAliveTime(30, TimeUnit.SECONDS)
            .keepAliveTimeout(5, TimeUnit.SECONDS)
            .build();
        
        String connectionId = "grpc-" + targetService + "-" + connectionCounter.incrementAndGet();
        return new GrpcConnection(connectionId, channel, targetService);
    }
    
    @Override
    public boolean validate(GrpcConnection connection) {
        return connection != null && connection.isHealthy();
    }
    
    @Override
    public void destroy(GrpcConnection connection) {
        if (connection != null) {
            connection.close();
        }
    }
}

// ========== ConnectionPoolManager - использует ConnectionPool ==========
public class ConnectionPoolManager {
    private static final Logger logger = LoggerFactory.getLogger(ConnectionPoolManager.class);
    private static final ConcurrentHashMap<String, ConnectionPool<GrpcConnection>> pools = new ConcurrentHashMap<>();
    private static final Object lock = new Object();
    
    public static ConnectionPool<GrpcConnection> getPool(String serviceName, String host, int port) {
        return pools.computeIfAbsent(serviceName, k -> {
            synchronized (lock) {
                ConnectionPool.PoolConfig config = new ConnectionPool.PoolConfig()
                    .maxSize(20)
                    .minSize(5)
                    .connectionTimeout(30000)
                    .healthCheckInterval(60000)
                    .targetService(serviceName);
                
                GrpcConnectionFactory factory = new GrpcConnectionFactory(host, port, serviceName);
                ConnectionPool<GrpcConnection> pool = new ConnectionPool<>(factory, config);
                
                logger.info("Created connection pool for service: {} at {}:{}", serviceName, host, port);
                return pool;
            }
        });
    }
    
    public static ConnectionPool<GrpcConnection> getGoPool() {
        return getPool("go", "localhost", 8082);
    }
    
    public static ConnectionPool<GrpcConnection> getElixirPool() {
        return getPool("elixir", "localhost", 4000);
    }
    
    public static ConnectionPool<GrpcConnection> getPythonPool() {
        return getPool("python", "localhost", 50052);
    }
    
    public static void shutdownAll() {
        logger.info("Shutting down all connection pools");
        for (ConnectionPool<GrpcConnection> pool : pools.values()) {
            pool.shutdown();
        }
        pools.clear();
    }
    
    public static Map<String, ConnectionPool.PoolStats> getAllStats() {
        Map<String, ConnectionPool.PoolStats> stats = new ConcurrentHashMap<>();
        pools.forEach((name, pool) -> stats.put(name, pool.getStats()));
        return stats;
    }
}