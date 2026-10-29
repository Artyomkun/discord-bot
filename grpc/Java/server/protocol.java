package com.bot.grpc.server;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.regex.Pattern;
import com.bot.grpc.server.metrics.ServerMetrics;
import com.bot.grpc.server.metrics.ServerMetricsCollector;

/**
 * Protocol utilities for gRPC server with server-side metrics integration.
 */
public class protocol {
    private static final Logger logger = Logger.getLogger(protocol.class.getName());
    
    // Серверные метрики
    private static ServerMetricsCollector serverMetrics = ServerMetricsCollector.getInstance();
    
    // Статистика
    private static final AtomicLong totalRequests = new AtomicLong(0);
    private static final AtomicLong successfulRequests = new AtomicLong(0);
    private static final AtomicLong failedRequests = new AtomicLong(0);
    private static final AtomicLong totalRequestDuration = new AtomicLong(0);
    private static final ConcurrentHashMap<String, MethodStats> methodStats = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, AtomicLong> errorStats = new ConcurrentHashMap<>();
    
    // Метрики подключенных сервисов (Go, Elixir, Python)
    private static final ConcurrentHashMap<String, ServiceHealth> serviceHealth = new ConcurrentHashMap<>();
    
    // Паттерны валидации
    private static final Pattern USER_ID_PATTERN = Pattern.compile("^[0-9]{17,20}$");
    private static final Pattern GUILD_ID_PATTERN = Pattern.compile("^[0-9]{17,20}$");
    private static final Pattern CHANNEL_ID_PATTERN = Pattern.compile("^[0-9]{17,20}$");
    private static final Pattern COMMAND_NAME_PATTERN = Pattern.compile("^[a-zA-Z][a-zA-Z0-9_]*$");
    
    // Rate limiting
    private static final ConcurrentHashMap<String, RateLimiter> rateLimiters = new ConcurrentHashMap<>();
    private static final int DEFAULT_RATE_LIMIT = 5;
    
    /**
     * Health status of connected services
     */
    public static class ServiceHealth {
        private volatile boolean healthy = true;
        private String lastError = null;
        private long lastHeartbeat = System.currentTimeMillis();
        private AtomicLong totalRequests = new AtomicLong(0);
        private AtomicLong failedRequests = new AtomicLong(0);
        
        public void reportHealthy() {
            this.healthy = true;
            this.lastHeartbeat = System.currentTimeMillis();
            this.lastError = null;
        }
        
        public void reportUnhealthy(String error) {
            this.healthy = false;
            this.lastError = error;
        }
        
        public void recordRequest(boolean success) {
            totalRequests.incrementAndGet();
            if (!success) {
                failedRequests.incrementAndGet();
            }
        }
        
        public boolean isHealthy() { return healthy; }
        public String getLastError() { return lastError; }
        public long getLastHeartbeat() { return lastHeartbeat; }
        public long getTotalRequests() { return totalRequests.get(); }
        public long getFailedRequests() { return failedRequests.get(); }
        public double getErrorRate() {
            long total = totalRequests.get();
            return total > 0 ? (failedRequests.get() * 100.0 / total) : 0;
        }
    }
    
    // ========== МЕТОДЫ ДЛЯ СЕРВЕРНЫХ МЕТРИК ==========
    
    /**
     * Записать входящий запрос на сервер
     */
    public static void recordRequest(String method, boolean success, long durationMs) {
        totalRequests.incrementAndGet();
        totalRequestDuration.addAndGet(durationMs);
        
        if (success) {
            successfulRequests.incrementAndGet();
        } else {
            failedRequests.incrementAndGet();
        }
        
        methodStats.computeIfAbsent(method, k -> new MethodStats())
                  .record(success, durationMs);
        
        // Записываем в серверные метрики
        if (serverMetrics != null) {
            serverMetrics.recordRequest(method, durationMs, success);
        }
        
        if (durationMs > 1000) {
            logger.warning(String.format("Slow request: %s took %dms", method, durationMs));
        }
    }
    
    /**
     * Записать ошибку на сервере
     */
    public static void recordError(ErrorCode error) {
        errorStats.computeIfAbsent(error.name(), k -> new AtomicLong(0))
                  .incrementAndGet();
        
        if (serverMetrics != null) {
            serverMetrics.recordError(error.name());
        }
        
        if (!error.isSuccess()) {
            logger.log(error.getCategory() == ErrorCategory.INTERNAL ? Level.SEVERE : Level.WARNING,
                      "Error: " + error.name() + " - " + error.getMessage());
        }
    }
    
    /**
     * Обновить статус подключенного сервиса
     */
    public static void updateServiceHealth(String serviceName, boolean healthy, String message) {
        ServiceHealth health = serviceHealth.computeIfAbsent(serviceName, k -> new ServiceHealth());
        
        if (healthy) {
            health.reportHealthy();
            logger.info(String.format("✅ Service %s is healthy", serviceName));
        } else {
            health.reportUnhealthy(message);
            logger.warning(String.format("⚠️ Service %s is UNHEALTHY: %s", serviceName, message));
            
            if (serverMetrics != null) {
                serverMetrics.recordError(serviceName + "_unhealthy");
                serverMetrics.triggerAlert("warning", 
                    String.format("Service %s is unhealthy", serviceName));
            }
        }
    }
    
    /**
     * Записать вызов в подключенный сервис (Go/Elixir/Python)
     */
    public static void recordServiceCall(String serviceName, String command, 
                                          boolean success, long latencyMs, String error) {
        ServiceHealth health = serviceHealth.computeIfAbsent(serviceName, k -> new ServiceHealth());
        health.recordRequest(success);
        
        if (serverMetrics != null) {
            String methodName = serviceName + "." + command;
            serverMetrics.recordRequest(methodName, latencyMs, success);
            
            if (!success) {
                serverMetrics.recordError(serviceName + "_error");
            }
        }
        
        if (!success) {
            logger.warning(String.format("Service %s call failed: %s (latency=%dms)", 
                serviceName, error, latencyMs));
        }
    }
    
    /**
     * Получить здоровье сервиса
     */
    public static ServiceHealth getServiceHealth(String serviceName) {
        return serviceHealth.get(serviceName);
    }
    
    /**
     * Получить статистику всех сервисов
     */
    public static Map<String, Object> getAllServicesHealth() {
        Map<String, Object> result = new HashMap<>();
        serviceHealth.forEach((name, health) -> {
            Map<String, Object> info = new HashMap<>();
            info.put("healthy", health.isHealthy());
            info.put("last_heartbeat", health.getLastHeartbeat());
            info.put("last_error", health.getLastError());
            info.put("total_requests", health.getTotalRequests());
            info.put("failed_requests", health.getFailedRequests());
            info.put("error_rate", health.getErrorRate());
            result.put(name, info);
        });
        return result;
    }
    
    // ========== СТАТИСТИКА ==========
    
    public static Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        long total = totalRequests.get();
        long success = successfulRequests.get();
        
        stats.put("total_requests", total);
        stats.put("successful_requests", success);
        stats.put("failed_requests", failedRequests.get());
        stats.put("success_rate", total > 0 ? (success * 100.0 / total) : 0);
        stats.put("avg_duration_ms", total > 0 ? totalRequestDuration.get() / (double) total : 0);
        
        Map<String, Object> methods = new HashMap<>();
        methodStats.forEach((k, v) -> methods.put(k, v.toMap()));
        stats.put("methods", methods);
        
        Map<String, Long> errors = new HashMap<>();
        errorStats.forEach((k, v) -> errors.put(k, v.get()));
        stats.put("errors", errors);
        
        stats.put("services_health", getAllServicesHealth());
        stats.put("rate_limiters_active", rateLimiters.size());
        
        return stats;
    }
    
    public static void resetStats() {
        totalRequests.set(0);
        successfulRequests.set(0);
        failedRequests.set(0);
        totalRequestDuration.set(0);
        methodStats.clear();
        errorStats.clear();
        rateLimiters.clear();
        serviceHealth.clear();
        logger.info("Protocol statistics reset");
    }
    
    // ========== ВАЛИДАЦИЯ ==========
    
    public static boolean checkRateLimit(String userId) {
        String key = "user:" + userId;
        RateLimiter limiter = rateLimiters.computeIfAbsent(key, 
            k -> new RateLimiter(DEFAULT_RATE_LIMIT, 1000));
        return limiter.allow();
    }
    
    public static ValidationResult validateCommand(Command cmd) {
        if (cmd == null) {
            return ValidationResult.error("Command is null", ErrorCode.INVALID_PARAMS);
        }
        
        if (cmd.getType() == null || cmd.getType().isEmpty()) {
            return ValidationResult.error("Command type is required", ErrorCode.MISSING_PARAMS);
        }
        
        if (!COMMAND_NAME_PATTERN.matcher(cmd.getType()).matches()) {
            return ValidationResult.error("Invalid command name", ErrorCode.INVALID_PARAMS);
        }
        
        if (cmd.getUserId() == null || cmd.getUserId().isEmpty()) {
            return ValidationResult.error("User ID is required", ErrorCode.MISSING_PARAMS);
        }
        
        if (!USER_ID_PATTERN.matcher(cmd.getUserId()).matches()) {
            return ValidationResult.error("Invalid user ID", ErrorCode.INVALID_USER_ID);
        }
        
        if (cmd.getGuildId() != null && !cmd.getGuildId().isEmpty()) {
            if (!GUILD_ID_PATTERN.matcher(cmd.getGuildId()).matches()) {
                return ValidationResult.error("Invalid guild ID", ErrorCode.INVALID_GUILD_ID);
            }
        }
        
        return ValidationResult.success();
    }
    
    // ========== ВСПОМОГАТЕЛЬНЫЕ КЛАССЫ ==========
    
    public static class MethodStats {
        private final AtomicLong count = new AtomicLong(0);
        private final AtomicLong successCount = new AtomicLong(0);
        private final AtomicLong errorCount = new AtomicLong(0);
        private final AtomicLong totalDuration = new AtomicLong(0);
        private final AtomicLong maxDuration = new AtomicLong(0);
        private final AtomicLong minDuration = new AtomicLong(Long.MAX_VALUE);
        
        public void record(boolean success, long durationMs) {
            count.incrementAndGet();
            totalDuration.addAndGet(durationMs);
            if (success) successCount.incrementAndGet();
            else errorCount.incrementAndGet();
            maxDuration.updateAndGet(max -> Math.max(max, durationMs));
            minDuration.updateAndGet(min -> Math.min(min, durationMs));
        }
        
        public Map<String, Object> toMap() {
            Map<String, Object> map = new HashMap<>();
            long c = count.get();
            map.put("count", c);
            map.put("success_count", successCount.get());
            map.put("error_count", errorCount.get());
            map.put("avg_duration_ms", c > 0 ? totalDuration.get() / (double) c : 0);
            map.put("max_duration_ms", maxDuration.get() == Long.MAX_VALUE ? 0 : maxDuration.get());
            map.put("min_duration_ms", minDuration.get() == Long.MAX_VALUE ? 0 : minDuration.get());
            map.put("success_rate", c > 0 ? (successCount.get() * 100.0 / c) : 0);
            return map;
        }
    }
    
    private static class RateLimiter {
        private final AtomicLong lastReset = new AtomicLong(System.currentTimeMillis());
        private final AtomicLong counter = new AtomicLong(0);
        private final int limit;
        private final long windowMs;
        
        RateLimiter(int limit, long windowMs) {
            this.limit = limit;
            this.windowMs = windowMs;
        }
        
        boolean allow() {
            long now = System.currentTimeMillis();
            long resetTime = lastReset.get();
            if (now - resetTime >= windowMs) {
                if (lastReset.compareAndSet(resetTime, now)) counter.set(0);
            }
            return counter.incrementAndGet() <= limit;
        }
    }
    
    public static class ValidationResult {
        private final boolean valid;
        private final String message;
        private final ErrorCode code;
        
        public ValidationResult(boolean valid) { this(valid, null, null); }
        public ValidationResult(boolean valid, String message, ErrorCode code) {
            this.valid = valid;
            this.message = message;
            this.code = code;
        }
        
        public boolean isValid() { return valid; }
        public String getMessage() { return message; }
        public ErrorCode getCode() { return code; }
        
        public static ValidationResult success() { return new ValidationResult(true); }
        public static ValidationResult error(String message, ErrorCode code) {
            return new ValidationResult(false, message, code);
        }
    }
    
    public enum ErrorCategory { SUCCESS, CLIENT, SERVICE, BUSINESS, INTERNAL }
    
    public enum ErrorCode {
        SUCCESS(0, "Success", ErrorCategory.SUCCESS),
        UNKNOWN_COMMAND(1001, "Unknown command", ErrorCategory.CLIENT),
        INVALID_PARAMS(1002, "Invalid parameters", ErrorCategory.CLIENT),
        MISSING_PARAMS(1003, "Missing parameters", ErrorCategory.CLIENT),
        RATE_LIMITED(1007, "Rate limited", ErrorCategory.CLIENT),
        INVALID_USER_ID(1008, "Invalid user ID", ErrorCategory.CLIENT),
        INVALID_GUILD_ID(1009, "Invalid guild ID", ErrorCategory.CLIENT),
        SERVICE_UNAVAILABLE(2001, "Service unavailable", ErrorCategory.SERVICE),
        TIMEOUT(2002, "Request timeout", ErrorCategory.SERVICE),
        INTERNAL_ERROR(5000, "Internal error", ErrorCategory.INTERNAL);
        
        private final int code;
        private final String message;
        private final ErrorCategory category;
        
        ErrorCode(int code, String message, ErrorCategory category) {
            this.code = code;
            this.message = message;
            this.category = category;
        }
        
        public int getCode() { return code; }
        public String getMessage() { return message; }
        public ErrorCategory getCategory() { return category; }
        public boolean isSuccess() { return this == SUCCESS; }
    }
    
    public static class Command {
        private String type;
        private String userId;
        private String guildId;
        private String channelId;
        private Map<String, Object> params = new HashMap<>();
        
        public Command(String type, String userId, String guildId) {
            this.type = type;
            this.userId = userId;
            this.guildId = guildId;
        }
        
        public String getType() { return type; }
        public String getUserId() { return userId; }
        public String getGuildId() { return guildId; }
        public String getChannelId() { return channelId; }
        public Map<String, Object> getParams() { return params; }
        public void setChannelId(String channelId) { this.channelId = channelId; }
        public void addParam(String key, Object value) { params.put(key, value); }
    }
}