package com.bot.grpc.server;

import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.StatusRuntimeException;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Enhanced connection pool for gRPC channels with improved error handling,
 * connection validation, and monitoring capabilities.
 */
public class connection_pool {
    private static final Logger logger = Logger.getLogger(connection_pool.class.getName());
    
    // Configuration parameters
    private static final int MAX_CONNECTIONS = Integer.getInteger("grpc.pool.max.connections", 10);
    private static final int MIN_CONNECTIONS = Integer.getInteger("grpc.pool.min.connections", 2);
    private static final long IDLE_TIMEOUT_MS = Long.getLong("grpc.pool.idle.timeout", 60000); // 1 minute
    private static final long CONNECTION_TIMEOUT_MS = Long.getLong("grpc.pool.connection.timeout", 30000); // 30 seconds
    private static final long HEALTH_CHECK_INTERVAL_MS = Long.getLong("grpc.pool.health.check.interval", 30000); // 30 seconds
    private static final long MAX_CONNECTION_LIFETIME_MS = Long.getLong("grpc.pool.max.lifetime", 3600000); // 1 hour
    
    private static final ConcurrentHashMap<String, PooledChannel> pools = new ConcurrentHashMap<>();
    private static final ScheduledExecutorService scheduler = Executors.newScheduledThreadPool(2);
    private static volatile boolean isShuttingDown = false;
    
    /**
     * Enhanced PooledChannel with additional metadata
     */
    static class PooledChannel {
        final ManagedChannel channel;
        final String address;
        final long createdAt;
        volatile long lastUsed;
        final AtomicInteger refCount;
        volatile boolean isHealthy;
        volatile boolean isClosing;
        
        PooledChannel(ManagedChannel channel, String address) {
            this.channel = channel;
            this.address = address;
            this.createdAt = System.currentTimeMillis();
            this.lastUsed = System.currentTimeMillis();
            this.refCount = new AtomicInteger(1);
            this.isHealthy = true;
            this.isClosing = false;
        }
        
        boolean isExpired() {
            return System.currentTimeMillis() - createdAt > MAX_CONNECTION_LIFETIME_MS;
        }
        
        boolean isIdle() {
            return refCount.get() <= 0 && (System.currentTimeMillis() - lastUsed) > IDLE_TIMEOUT_MS;
        }
        
        void incrementRef() {
            refCount.incrementAndGet();
            lastUsed = System.currentTimeMillis();
        }
        
        boolean decrementRef() {
            int newCount = refCount.decrementAndGet();
            lastUsed = System.currentTimeMillis();
            return newCount <= 0;
        }
        
        void markUnhealthy() {
            isHealthy = false;
        }
        
        void close() {
            if (isClosing) return;
            isClosing = true;
            
            try {
                channel.shutdown();
                if (!channel.awaitTermination(5, TimeUnit.SECONDS)) {
                    channel.shutdownNow();
                }
                logger.info(String.format("🔌 Closed gRPC channel for %s (lifetime: %d ms)", 
                    address, System.currentTimeMillis() - createdAt));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                channel.shutdownNow();
                logger.warning("Interrupted while closing channel for " + address);
            }
        }
    }
    
    /**
     * Get or create a channel for the specified address with validation
     */
    public static ManagedChannel getChannel(String host, int port) throws ConnectionPoolException {
        if (isShuttingDown) {
            throw new ConnectionPoolException("Connection pool is shutting down");
        }
        
        String key = host + ":" + port;
        
        try {
            PooledChannel pooled = pools.compute(key, (k, existing) -> {
                // Check if existing channel is valid
                if (existing != null && isValidChannel(existing)) {
                    existing.incrementRef();
                    logger.fine(String.format("✅ Reusing channel for %s (refs: %d)", 
                        key, existing.refCount.get()));
                    return existing;
                }
                
                // Close existing if invalid
                if (existing != null) {
                    logger.warning(String.format("⚠️ Creating new channel for %s (old: unhealthy/expired)", key));
                    existing.close();
                }
                
                // Create new channel
                ManagedChannel channel = createChannel(host, port);
                logger.info(String.format("✅ Created new gRPC channel for %s", key));
                return new PooledChannel(channel, key);
            });
            
            return pooled.channel;
            
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Failed to get channel for " + key, e);
            throw new ConnectionPoolException("Failed to create connection to " + key, e);
        }
    }
    
    /**
     * Create a new ManagedChannel with optimal configuration
     */
    private static ManagedChannel createChannel(String host, int port) {
        return ManagedChannelBuilder.forAddress(host, port)
                .usePlaintext()
                .keepAliveTime(30, TimeUnit.SECONDS)
                .keepAliveTimeout(10, TimeUnit.SECONDS)
                .keepAliveWithoutCalls(true)
                .maxInboundMessageSize(100 * 1024 * 1024) // 100MB
                .idleTimeout(IDLE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                .maxRetryAttempts(3)
                .enableRetry()
                .build();
    }
    
    /**
     * Validate if a channel is still usable
     */
    private static boolean isValidChannel(PooledChannel pooled) {
        if (pooled == null || pooled.isClosing) return false;
        
        ManagedChannel channel = pooled.channel;
        
        // Check channel state
        if (channel.isShutdown() || channel.isTerminated()) {
            return false;
        }
        
        // Check health flag
        if (!pooled.isHealthy) {
            return false;
        }
        
        // Check lifetime expiration
        if (pooled.isExpired()) {
            logger.fine(String.format("Channel for %s expired after %d ms", 
                pooled.address, System.currentTimeMillis() - pooled.createdAt));
            return false;
        }
        
        return true;
    }
    
    /**
     * Release a channel (decrement reference count)
     */
    public static void releaseChannel(String host, int port) {
        releaseChannel(host, port, false);
    }
    
    /**
     * Release a channel with option to force close
     */
    public static void releaseChannel(String host, int port, boolean forceClose) {
        String key = host + ":" + port;
        
        pools.computeIfPresent(key, (k, pooled) -> {
            boolean shouldClose = forceClose || pooled.decrementRef();
            
            if (shouldClose) {
                logger.fine(String.format("📤 Closing channel for %s (last reference released)", key));
                pooled.close();
                return null;
            }
            
            logger.fine(String.format("📤 Released channel for %s (refs: %d)", 
                key, pooled.refCount.get()));
            return pooled;
        });
    }
    
    /**
     * Mark a channel as unhealthy (to be replaced on next use)
     */
    public static void markUnhealthy(String host, int port) {
        String key = host + ":" + port;
        PooledChannel pooled = pools.get(key);
        if (pooled != null) {
            pooled.markUnhealthy();
            logger.warning(String.format("⚠️ Marked channel for %s as unhealthy", key));
        }
    }
    
    /**
     * Execute operation with automatic channel management
     */
    public static <T> T withChannel(String host, int port, ChannelOperation<T> operation) 
            throws ConnectionPoolException {
        ManagedChannel channel = null;
        try {
            channel = getChannel(host, port);
            return operation.execute(channel);
        } catch (StatusRuntimeException e) {
            // If the error indicates connection issues, mark the channel as unhealthy
            if (e.getStatus().getCode() == io.grpc.Status.Code.UNAVAILABLE ||
                e.getStatus().getCode() == io.grpc.Status.Code.DEADLINE_EXCEEDED) {
                markUnhealthy(host, port);
            }
            throw new ConnectionPoolException("gRPC operation failed", e);
        } catch (Exception e) {
            throw new ConnectionPoolException("Operation failed", e);
        } finally {
            if (channel != null) {
                releaseChannel(host, port);
            }
        }
    }
    
    /**
     * Perform health check on all channels
     */
    private static void performHealthCheck() {
        if (isShuttingDown) return;
        
        pools.forEach((key, pooled) -> {
            if (pooled.isClosing) return;
            
            try {
                ManagedChannel channel = pooled.channel;
                
                // Check if channel is still responsive
                if (channel.isShutdown() || channel.isTerminated()) {
                    logger.warning(String.format("Channel for %s is terminated", key));
                    pooled.markUnhealthy();
                    return;
                }
                
                // Optional: Perform actual health check via gRPC
                // This would require a health check service implementation
                
                // Reset health flag if it was previously unhealthy
                if (!pooled.isHealthy) {
                    logger.info(String.format("Channel for %s is healthy again", key));
                    pooled.isHealthy = true;
                }
                
            } catch (Exception e) {
                logger.log(Level.WARNING, String.format("Health check failed for %s", key), e);
                pooled.markUnhealthy();
            }
        });
    }
    
    /**
     * Clean up idle and unhealthy connections
     */
    public static void cleanupIdle() {
        if (isShuttingDown) return;
        
        int beforeCount = pools.size();
        pools.entrySet().removeIf(entry -> {
            PooledChannel pooled = entry.getValue();
            
            // Remove if idle or unhealthy
            if (pooled.isIdle() || !pooled.isHealthy) {
                pooled.close();
                logger.info(String.format("🧹 Cleaned up %s channel for %s (idle: %b, healthy: %b)",
                    pooled.isIdle() ? "idle" : "unhealthy",
                    entry.getKey(),
                    pooled.isIdle(),
                    pooled.isHealthy));
                return true;
            }
            
            return false;
        });
        
        int afterCount = pools.size();
        if (beforeCount != afterCount) {
            logger.info(String.format("Cleaned up %d channels", beforeCount - afterCount));
        }
    }
    
    /**
     * Ensure minimum number of connections
     */
    private static void ensureMinimumConnections() {
        if (isShuttingDown) return;
        
        // This is a simplified version - in production you'd want to know
        // which endpoints need minimum connections
        pools.forEach((key, pooled) -> {
            // For now, just log if we're below minimum for any endpoint
            // You'd need to track per-endpoint requirements
            int totalForEndpoint = (int) pools.values().stream()
                .filter(p -> p.address.equals(key))
                .count();
            
            if (totalForEndpoint < MIN_CONNECTIONS) {
                logger.fine(String.format("Below minimum connections for %s: %d < %d", 
                    key, totalForEndpoint, MIN_CONNECTIONS));
            }
        });
    }
    
    /**
     * Close all channels and shutdown the pool
     */
    public static void shutdownAll() {
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
        
        pools.forEach((key, pooled) -> {
            pooled.close();
        });
        pools.clear();
        
        logger.info("Connection pool shutdown complete");
    }
    
    /**
     * Start background maintenance tasks
     */
    public static void startMaintenanceTasks() {
        // Health check task
        scheduler.scheduleAtFixedRate(() -> {
            try {
                performHealthCheck();
            } catch (Exception e) {
                logger.log(Level.SEVERE, "Error in health check", e);
            }
        }, HEALTH_CHECK_INTERVAL_MS, HEALTH_CHECK_INTERVAL_MS, TimeUnit.MILLISECONDS);
        
        // Cleanup idle connections task
        scheduler.scheduleAtFixedRate(() -> {
            try {
                cleanupIdle();
            } catch (Exception e) {
                logger.log(Level.SEVERE, "Error in cleanup", e);
            }
        }, IDLE_TIMEOUT_MS / 2, IDLE_TIMEOUT_MS / 2, TimeUnit.MILLISECONDS);
        
        // Monitor and ensure minimum connections
        scheduler.scheduleAtFixedRate(() -> {
            try {
                ensureMinimumConnections();
            } catch (Exception e) {
                logger.log(Level.SEVERE, "Error in min connections check", e);
            }
        }, 1, 1, TimeUnit.MINUTES);
        
        logger.info("Started connection pool maintenance tasks");
    }
    
    /**
     * Get pool statistics
     */
    public static PoolStats getStats() {
        PoolStats stats = new PoolStats();
        
        pools.forEach((key, pooled) -> {
            stats.addEndpoint(key, 
                pooled.refCount.get(),
                System.currentTimeMillis() - pooled.createdAt,
                pooled.isHealthy);
        });
        
        return stats;
    }
    
    /**
     * Get formatted statistics string
     */
    public static String getStatsString() {
        StringBuilder sb = new StringBuilder();
        sb.append("=== Connection Pool Statistics ===\n");
        sb.append(String.format("Total connections: %d\n", pools.size()));
        sb.append(String.format("Shutting down: %b\n\n", isShuttingDown));
        
        pools.forEach((key, pooled) -> {
            sb.append(String.format("  %s:\n", key))
              .append(String.format("    Refs: %d\n", pooled.refCount.get()))
              .append(String.format("    Age: %d ms\n", System.currentTimeMillis() - pooled.createdAt))
              .append(String.format("    Idle: %d ms\n", System.currentTimeMillis() - pooled.lastUsed))
              .append(String.format("    Healthy: %b\n", pooled.isHealthy))
              .append(String.format("    State: %s\n", pooled.channel.getState(true)));
        });
        
        return sb.toString();
    }
    
    /**
     * Functional interface for channel operations
     */
    @FunctionalInterface
    public interface ChannelOperation<T> {
        T execute(ManagedChannel channel) throws Exception;
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
     * Statistics class
     */
    public static class PoolStats {
        private final ConcurrentHashMap<String, EndpointStats> endpointStats = new ConcurrentHashMap<>();
        
        public static class EndpointStats {
            public final int activeConnections;
            public final long age;
            public final boolean healthy;
            
            EndpointStats(int active, long age, boolean healthy) {
                this.activeConnections = active;
                this.age = age;
                this.healthy = healthy;
            }
        }
        
        void addEndpoint(String key, int active, long age, boolean healthy) {
            endpointStats.put(key, new EndpointStats(active, age, healthy));
        }
        
        public ConcurrentHashMap<String, EndpointStats> getEndpointStats() {
            return endpointStats;
        }
        
        public int getTotalConnections() {
            return endpointStats.size();
        }
    }
    
    // Static initializer - start maintenance tasks
    static {
        startMaintenanceTasks();
        
        // Add shutdown hook
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            logger.info("JVM shutdown hook triggered");
            shutdownAll();
        }));
    }
}