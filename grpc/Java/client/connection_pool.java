package com.bot.grpc.client;

import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.StatusRuntimeException;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.Map;
import java.util.HashMap;
import java.util.List;
import java.util.ArrayList;
import java.util.logging.Logger;
import java.util.logging.Level;

/**
 * Connection pool for gRPC client connections to multiple servers
 * Supports multiple endpoints with load balancing and failover
 */
public class connection_pool {
    private static final Logger logger = Logger.getLogger(connection_pool.class.getName());
    
    // Singleton instance
    private static volatile connection_pool instance;
    private static final Object lock = new Object();
    
    // Configuration
    private static final int DEFAULT_MAX_CONNECTIONS_PER_ENDPOINT = 10;
    private static final int DEFAULT_MIN_CONNECTIONS_PER_ENDPOINT = 2;
    private static final long DEFAULT_IDLE_TIMEOUT_MS = 60000; // 1 minute
    private static final long DEFAULT_CONNECTION_TIMEOUT_MS = 30000; // 30 seconds
    private static final long DEFAULT_HEALTH_CHECK_INTERVAL_MS = 30000; // 30 seconds
    private static final long DEFAULT_MAX_CONNECTION_LIFETIME_MS = 3600000; // 1 hour
    
    // Connection pools per endpoint
    private final Map<String, EndpointPool> endpointPools = new ConcurrentHashMap<>();
    private final List<String> endpoints = new CopyOnWriteArrayList<>();
    private final AtomicInteger currentEndpointIndex = new AtomicInteger(0);
    
    // Load balancing strategy
    public enum LoadBalancingStrategy {
        ROUND_ROBIN,
        RANDOM,
        LEAST_CONNECTIONS,
        FASTEST_RESPONSE
    }
    
    private LoadBalancingStrategy strategy = LoadBalancingStrategy.ROUND_ROBIN;
    private final Map<String, Long> responseTimes = new ConcurrentHashMap<>();
    
    // Background maintenance
    private final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(2);
    private volatile boolean isShuttingDown = false;
    
    /**
     * Pool configuration
     */
    public static class PoolConfig {
        private int maxConnectionsPerEndpoint = DEFAULT_MAX_CONNECTIONS_PER_ENDPOINT;
        private int minConnectionsPerEndpoint = DEFAULT_MIN_CONNECTIONS_PER_ENDPOINT;
        private long idleTimeoutMs = DEFAULT_IDLE_TIMEOUT_MS;
        private long connectionTimeoutMs = DEFAULT_CONNECTION_TIMEOUT_MS;
        private long healthCheckIntervalMs = DEFAULT_HEALTH_CHECK_INTERVAL_MS;
        private long maxConnectionLifetimeMs = DEFAULT_MAX_CONNECTION_LIFETIME_MS;
        private LoadBalancingStrategy strategy = LoadBalancingStrategy.ROUND_ROBIN;
        
        public PoolConfig maxConnectionsPerEndpoint(int max) {
            this.maxConnectionsPerEndpoint = max;
            return this;
        }
        
        public PoolConfig minConnectionsPerEndpoint(int min) {
            this.minConnectionsPerEndpoint = min;
            return this;
        }
        
        public PoolConfig idleTimeoutMs(long timeoutMs) {
            this.idleTimeoutMs = timeoutMs;
            return this;
        }
        
        public PoolConfig connectionTimeoutMs(long timeoutMs) {
            this.connectionTimeoutMs = timeoutMs;
            return this;
        }
        
        public PoolConfig healthCheckIntervalMs(long intervalMs) {
            this.healthCheckIntervalMs = intervalMs;
            return this;
        }
        
        public PoolConfig maxConnectionLifetimeMs(long lifetimeMs) {
            this.maxConnectionLifetimeMs = lifetimeMs;
            return this;
        }
        
        public PoolConfig loadBalancingStrategy(LoadBalancingStrategy strategy) {
            this.strategy = strategy;
            return this;
        }
        
        public LoadBalancingStrategy getStrategy() {
            return strategy;
        }
    }
    
    /**
     * Pool for a specific endpoint
     */
    private static class EndpointPool {
        private final String host;
        private final int port;
        private final String address;
        private final BlockingQueue<PooledChannel> availableConnections;
        private final List<PooledChannel> allConnections;
        private final AtomicInteger activeConnections;
        private final Semaphore connectionSemaphore;
        private final PoolConfig config;
        private volatile boolean isHealthy = true;
        private volatile boolean isClosing = false;
        private final AtomicLong lastHealthCheck = new AtomicLong(0);
        private final AtomicLong totalResponseTime = new AtomicLong(0);
        private final AtomicLong requestCount = new AtomicLong(0);
        
        EndpointPool(String host, int port, PoolConfig config) {
            this.host = host;
            this.port = port;
            this.address = host + ":" + port;
            this.config = config;
            this.availableConnections = new LinkedBlockingQueue<>();
            this.allConnections = new CopyOnWriteArrayList<>();
            this.activeConnections = new AtomicInteger(0);
            this.connectionSemaphore = new Semaphore(config.maxConnectionsPerEndpoint);
            
            initializePool();
        }
        
        private void initializePool() {
            for (int i = 0; i < config.minConnectionsPerEndpoint; i++) {
                try {
                    PooledChannel channel = createChannel();
                    allConnections.add(channel);
                    availableConnections.offer(channel);
                } catch (Exception e) {
                    logger.log(Level.WARNING, "Failed to create initial connection to " + address, e);
                }
            }
            logger.info(String.format("Initialized pool for %s with %d connections",
                address, allConnections.size()));
        }
        
        private PooledChannel createChannel() throws Exception {
            ManagedChannel managedChannel = ManagedChannelBuilder.forAddress(host, port)
                .usePlaintext()
                .keepAliveTime(30, TimeUnit.SECONDS)
                .keepAliveTimeout(10, TimeUnit.SECONDS)
                .keepAliveWithoutCalls(true)
                .maxInboundMessageSize(100 * 1024 * 1024)
                .idleTimeout(config.idleTimeoutMs, TimeUnit.MILLISECONDS)
                .build();
            
            return new PooledChannel(managedChannel, address);
        }
        
        public ManagedChannel borrowChannel(long timeoutMs) throws InterruptedException, TimeoutException {
            if (isClosing) {
                throw new IllegalStateException("Pool is closing");
            }
            
            if (!connectionSemaphore.tryAcquire(timeoutMs, TimeUnit.MILLISECONDS)) {
                throw new TimeoutException("Could not acquire connection to " + address);
            }
            
            try {
                PooledChannel pooled = availableConnections.poll(timeoutMs, TimeUnit.MILLISECONDS);
                
                if (pooled == null && activeConnections.get() < config.maxConnectionsPerEndpoint) {
                    // Create new connection on demand
                    try {
                        pooled = createChannel();
                        allConnections.add(pooled);
                        logger.fine("Created new connection to " + address);
                    } catch (Exception e) {
                        connectionSemaphore.release();
                        throw new RuntimeException("Failed to create new connection", e);
                    }
                }
                
                if (pooled == null) {
                    connectionSemaphore.release();
                    throw new TimeoutException("No available connections to " + address);
                }
                
                activeConnections.incrementAndGet();
                pooled.markUsed();
                
                return pooled.getChannel();
                
            } catch (InterruptedException e) {
                connectionSemaphore.release();
                Thread.currentThread().interrupt();
                throw e;
            }
        }
        
        public void returnChannel(ManagedChannel channel) {
            if (channel == null) return;
            
            PooledChannel pooled = findPooledChannel(channel);
            if (pooled != null) {
                if (isClosing || !pooled.isHealthy()) {
                    closeConnection(pooled);
                } else {
                    availableConnections.offer(pooled);
                }
                activeConnections.decrementAndGet();
                connectionSemaphore.release();
            }
        }
        
        private PooledChannel findPooledChannel(ManagedChannel channel) {
            for (PooledChannel pooled : allConnections) {
                if (pooled.getChannel() == channel) {
                    return pooled;
                }
            }
            return null;
        }
        
        private void closeConnection(PooledChannel pooled) {
            allConnections.remove(pooled);
            pooled.close();
            logger.fine("Closed connection to " + address);
        }
        
        public void healthCheck() {
            if (isClosing) return;
            
            long now = System.currentTimeMillis();
            lastHealthCheck.set(now);
            
            boolean wasHealthy = isHealthy;
            boolean currentHealthy = checkHealth();
            
            if (currentHealthy != wasHealthy) {
                isHealthy = currentHealthy;
                logger.info(String.format("Health status for %s changed to: %s",
                    address, currentHealthy ? "HEALTHY" : "UNHEALTHY"));
            }
            
            // Clean up idle and expired connections
            cleanupConnections();
            
            // Replenish if needed
            if (currentHealthy && allConnections.size() < config.minConnectionsPerEndpoint) {
                replenishConnections();
            }
        }
        
        private boolean checkHealth() {
            // Try to get a connection and perform a quick health check
            ManagedChannel channel = null;
            try {
                channel = borrowChannel(5000);
                // Could perform a real health check via gRPC if available
                return true;
            } catch (Exception e) {
                return false;
            } finally {
                if (channel != null) {
                    returnChannel(channel);
                }
            }
        }
        
        private void cleanupConnections() {
            List<PooledChannel> toRemove = new ArrayList<>();
            
            for (PooledChannel pooled : allConnections) {
                if (pooled.isExpired(config.maxConnectionLifetimeMs) ||
                    pooled.isIdle(config.idleTimeoutMs) ||
                    !pooled.isHealthy()) {
                    toRemove.add(pooled);
                }
            }
            
            for (PooledChannel pooled : toRemove) {
                allConnections.remove(pooled);
                availableConnections.remove(pooled);
                pooled.close();
            }
            
            if (!toRemove.isEmpty()) {
                logger.fine(String.format("Cleaned up %d connections to %s", toRemove.size(), address));
            }
        }
        
        private void replenishConnections() {
            int needed = config.minConnectionsPerEndpoint - allConnections.size();
            for (int i = 0; i < needed; i++) {
                try {
                    PooledChannel pooled = createChannel();
                    allConnections.add(pooled);
                    availableConnections.offer(pooled);
                } catch (Exception e) {
                    logger.log(Level.WARNING, "Failed to replenish connection to " + address, e);
                }
            }
        }
        
        public void recordResponseTime(long responseTimeMs) {
            totalResponseTime.addAndGet(responseTimeMs);
            requestCount.incrementAndGet();
        }
        
        public double getAverageResponseTime() {
            long count = requestCount.get();
            return count > 0 ? totalResponseTime.get() / (double) count : Double.MAX_VALUE;
        }
        
        public int getActiveConnections() {
            return activeConnections.get();
        }
        
        public int getTotalConnections() {
            return allConnections.size();
        }
        
        public int getAvailableConnections() {
            return availableConnections.size();
        }
        
        public boolean isHealthy() {
            return isHealthy;
        }
        
        public String getAddress() {
            return address;
        }
        
        public void shutdown() {
            isClosing = true;
            for (PooledChannel pooled : allConnections) {
                pooled.close();
            }
            allConnections.clear();
            availableConnections.clear();
        }
        
        public Map<String, Object> getStats() {
            Map<String, Object> stats = new HashMap<>();
            stats.put("address", address);
            stats.put("healthy", isHealthy);
            stats.put("active_connections", getActiveConnections());
            stats.put("total_connections", getTotalConnections());
            stats.put("available_connections", getAvailableConnections());
            stats.put("avg_response_time_ms", getAverageResponseTime());
            return stats;
        }
    }
    
    /**
     * Pooled channel wrapper
     */
    private static class PooledChannel {
        private final ManagedChannel channel;
        private final String address;
        private final long createdAt;
        private volatile long lastUsed;
        private volatile boolean isHealthy;
        
        PooledChannel(ManagedChannel channel, String address) {
            this.channel = channel;
            this.address = address;
            this.createdAt = System.currentTimeMillis();
            this.lastUsed = System.currentTimeMillis();
            this.isHealthy = true;
        }
        
        ManagedChannel getChannel() {
            return channel;
        }
        
        void markUsed() {
            lastUsed = System.currentTimeMillis();
        }
        
        boolean isExpired(long maxLifetimeMs) {
            return System.currentTimeMillis() - createdAt > maxLifetimeMs;
        }
        
        boolean isIdle(long idleTimeoutMs) {
            return System.currentTimeMillis() - lastUsed > idleTimeoutMs;
        }
        
        boolean isHealthy() {
            return isHealthy && !channel.isShutdown() && !channel.isTerminated();
        }
        
        void markUnhealthy() {
            isHealthy = false;
        }
        
        void close() {
            channel.shutdown();
            try {
                if (!channel.awaitTermination(5, TimeUnit.SECONDS)) {
                    channel.shutdownNow();
                }
            } catch (InterruptedException e) {
                channel.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
    }
    
    private connection_pool() {
        this(new PoolConfig());
    }
    
    private connection_pool(PoolConfig config) {
        this.strategy = config.getStrategy();
        startMaintenanceTasks();
    }
    
    /**
     * Get singleton instance
     */
    public static connection_pool getInstance() {
        if (instance == null) {
            synchronized (lock) {
                if (instance == null) {
                    instance = new connection_pool();
                }
            }
        }
        return instance;
    }
    
    /**
     * Get instance with custom config
     */
    public static connection_pool getInstance(PoolConfig config) {
        if (instance == null) {
            synchronized (lock) {
                if (instance == null) {
                    instance = new connection_pool(config);
                }
            }
        }
        return instance;
    }
    
    /**
     * Add an endpoint to the pool
     */
    public void addEndpoint(String host, int port) {
        String address = host + ":" + port;
        if (!endpointPools.containsKey(address)) {
            EndpointPool pool = new EndpointPool(host, port, new PoolConfig());
            endpointPools.put(address, pool);
            endpoints.add(address);
            logger.info("Added endpoint: " + address);
        }
    }
    
    /**
     * Add endpoint with custom config
     */
    public void addEndpoint(String host, int port, PoolConfig config) {
        String address = host + ":" + port;
        if (!endpointPools.containsKey(address)) {
            EndpointPool pool = new EndpointPool(host, port, config);
            endpointPools.put(address, pool);
            endpoints.add(address);
            logger.info("Added endpoint: " + address);
        }
    }
    
    /**
     * Remove an endpoint
     */
    public void removeEndpoint(String host, int port) {
        String address = host + ":" + port;
        EndpointPool pool = endpointPools.remove(address);
        if (pool != null) {
            pool.shutdown();
            endpoints.remove(address);
            logger.info("Removed endpoint: " + address);
        }
    }
    
    /**
     * Get a channel from the pool using current load balancing strategy
     */
    public ManagedChannel getChannel() throws ConnectionPoolException {
        return getChannel(null, 0);
    }
    
    /**
     * Get a channel from the pool with timeout
     */
    public ManagedChannel getChannel(String preferredHost, int preferredPort) throws ConnectionPoolException {
        if (endpointPools.isEmpty()) {
            throw new ConnectionPoolException("No endpoints configured");
        }
        
        // Try preferred endpoint first
        if (preferredHost != null && !preferredHost.isEmpty()) {
            String preferredAddress = preferredHost + ":" + preferredPort;
            EndpointPool preferredPool = endpointPools.get(preferredAddress);
            if (preferredPool != null && preferredPool.isHealthy()) {
                try {
                    return preferredPool.borrowChannel(5000);
                } catch (Exception e) {
                    logger.log(Level.FINE, "Preferred endpoint unavailable, falling back", e);
                }
            }
        }
        
        // Get healthy endpoints
        List<EndpointPool> healthyPools = new ArrayList<>();
        for (EndpointPool pool : endpointPools.values()) {
            if (pool.isHealthy()) {
                healthyPools.add(pool);
            }
        }
        
        if (healthyPools.isEmpty()) {
            throw new ConnectionPoolException("No healthy endpoints available");
        }
        
        // Select endpoint based on strategy
        EndpointPool selected = selectEndpoint(healthyPools);
        
        try {
            return selected.borrowChannel(10000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new ConnectionPoolException("Interrupted while waiting for connection", e);
        } catch (TimeoutException e) {
            throw new ConnectionPoolException("Timeout waiting for connection", e);
        } catch (Exception e) {
            throw new ConnectionPoolException("Failed to get connection", e);
        }
    }
    
    /**
     * Select endpoint based on load balancing strategy
     */
    private EndpointPool selectEndpoint(List<EndpointPool> healthyPools) {
        switch (strategy) {
            case ROUND_ROBIN:
                int index = Math.abs(currentEndpointIndex.getAndIncrement() % healthyPools.size());
                return healthyPools.get(index);
                
            case RANDOM:
                int randomIndex = ThreadLocalRandom.current().nextInt(healthyPools.size());
                return healthyPools.get(randomIndex);
                
            case LEAST_CONNECTIONS:
                return healthyPools.stream()
                    .min((a, b) -> Integer.compare(a.getActiveConnections(), b.getActiveConnections()))
                    .orElse(healthyPools.get(0));
                
            case FASTEST_RESPONSE:
                return healthyPools.stream()
                    .min((a, b) -> Double.compare(a.getAverageResponseTime(), b.getAverageResponseTime()))
                    .orElse(healthyPools.get(0));
                
            default:
                return healthyPools.get(0);
        }
    }
    
    /**
     * Return a channel to the pool
     */
    public void returnChannel(ManagedChannel channel) {
        if (channel == null) return;
        
        for (EndpointPool pool : endpointPools.values()) {
            pool.returnChannel(channel);
        }
    }
    
    /**
     * Record response time for an endpoint
     */
    public void recordResponseTime(String host, int port, long responseTimeMs) {
        String address = host + ":" + port;
        EndpointPool pool = endpointPools.get(address);
        if (pool != null) {
            pool.recordResponseTime(responseTimeMs);
        }
    }
    
    /**
     * Mark an endpoint as unhealthy
     */
    public void markUnhealthy(String host, int port) {
        String address = host + ":" + port;
        EndpointPool pool = endpointPools.get(address);
        if (pool != null) {
            logger.warning("Marking endpoint as unhealthy: " + address);
            // The health check will handle recovery
        }
    }
    
    /**
     * Start background maintenance tasks
     */
    private void startMaintenanceTasks() {
        // Health check task
        scheduler.scheduleAtFixedRate(() -> {
            if (!isShuttingDown) {
                performHealthChecks();
            }
        }, DEFAULT_HEALTH_CHECK_INTERVAL_MS, DEFAULT_HEALTH_CHECK_INTERVAL_MS, TimeUnit.MILLISECONDS);
        
        logger.info("Started connection pool maintenance tasks");
    }
    
    /**
     * Perform health checks on all endpoints
     */
    private void performHealthChecks() {
        for (EndpointPool pool : endpointPools.values()) {
            try {
                pool.healthCheck();
            } catch (Exception e) {
                logger.log(Level.WARNING, "Health check failed for " + pool.getAddress(), e);
            }
        }
    }
    
    /**
     * Get pool statistics
     */
    public Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("strategy", strategy.name());
        stats.put("total_endpoints", endpointPools.size());
        stats.put("healthy_endpoints", endpointPools.values().stream()
            .filter(EndpointPool::isHealthy).count());
        
        List<Map<String, Object>> endpointStats = new ArrayList<>();
        for (EndpointPool pool : endpointPools.values()) {
            endpointStats.add(pool.getStats());
        }
        stats.put("endpoints", endpointStats);
        
        return stats;
    }
    
    /**
     * Get formatted statistics string
     */
    public String getStatsString() {
        StringBuilder sb = new StringBuilder();
        sb.append("=== Connection Pool Statistics ===\n");
        sb.append(String.format("Strategy: %s\n", strategy));
        sb.append(String.format("Total endpoints: %d\n", endpointPools.size()));
        sb.append(String.format("Healthy endpoints: %d\n\n", 
            endpointPools.values().stream().filter(EndpointPool::isHealthy).count()));
        
        for (EndpointPool pool : endpointPools.values()) {
            sb.append(String.format("  %s:\n", pool.getAddress()));
            sb.append(String.format("    Healthy: %s\n", pool.isHealthy()));
            sb.append(String.format("    Active: %d\n", pool.getActiveConnections()));
            sb.append(String.format("    Total: %d\n", pool.getTotalConnections()));
            sb.append(String.format("    Available: %d\n", pool.getAvailableConnections()));
            sb.append(String.format("    Avg Response: %.2f ms\n", pool.getAverageResponseTime()));
        }
        
        return sb.toString();
    }
    
    /**
     * Shutdown all pools
     */
    public void shutdown() {
        logger.info("Shutting down connection pool...");
        isShuttingDown = true;
        
        scheduler.shutdown();
        try {
            if (!scheduler.awaitTermination(10, TimeUnit.SECONDS)) {
                scheduler.shutdownNow();
            }
        } catch (InterruptedException e) {
            scheduler.shutdownNow();
            Thread.currentThread().interrupt();
        }
        
        for (EndpointPool pool : endpointPools.values()) {
            pool.shutdown();
        }
        endpointPools.clear();
        
        logger.info("Connection pool shutdown complete");
    }
    
    /**
     * Set load balancing strategy
     */
    public void setLoadBalancingStrategy(LoadBalancingStrategy strategy) {
        this.strategy = strategy;
        logger.info("Load balancing strategy changed to: " + strategy);
    }
    
    /**
     * Custom exception for connection pool errors
     */
    public static class ConnectionPoolException extends Exception {
        public ConnectionPoolException(String message) {
            super(message);
        }
        
        public ConnectionPoolException(String message, Throwable cause) {
            super(message, cause);
        }
    }
    
    /**
     * Execute operation with automatic channel management
     */
    public static <T> T withChannel(connection_pool pool, ChannelOperation<T> operation) 
            throws ConnectionPoolException {
        ManagedChannel channel = null;
        try {
            channel = pool.getChannel();
            return operation.execute(channel);
        } catch (Exception e) {
            throw new ConnectionPoolException("Operation failed", e);
        } finally {
            if (channel != null) {
                pool.returnChannel(channel);
            }
        }
    }
    
    /**
     * Functional interface for channel operations
     */
    @FunctionalInterface
    public interface ChannelOperation<T> {
        T execute(ManagedChannel channel) throws Exception;
    }
    
    // Static initializer - add shutdown hook
    static {
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            if (instance != null) {
                instance.shutdown();
            }
        }));
    }
}