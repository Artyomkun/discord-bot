package com.bot.grpc.client;

import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.Map;
import java.util.HashMap;
import java.util.logging.Logger;
import java.util.logging.Level;

/**
 * Клиентские метрики для отслеживания запросов к серверу
 * 
 * Собирает:
 * - Количество запросов по методам
 * - Время ответа
 * - Ошибки
 * - Статус соединения
 */
public class metrics {
    private static final Logger logger = Logger.getLogger(metrics.class.getName());
    
    private static volatile metrics instance;
    private static final Object lock = new Object();
    
    // Метрики запросов
    private final AtomicLong totalRequests = new AtomicLong(0);
    private final AtomicLong successfulRequests = new AtomicLong(0);
    private final AtomicLong failedRequests = new AtomicLong(0);
    private final AtomicLong totalLatency = new AtomicLong(0);
    
    // Метрики по методам
    private final Map<String, MethodMetrics> methodMetrics = new ConcurrentHashMap<>();
    
    // Метрики соединения
    private final AtomicLong reconnectAttempts = new AtomicLong(0);
    private final AtomicLong reconnectSuccess = new AtomicLong(0);
    private final AtomicLong reconnectFailures = new AtomicLong(0);
    private volatile long lastConnectionTime = 0;
    private volatile boolean isConnected = false;
    
    // История запросов для скользящего окна
    private final SlidingWindow requestHistory = new SlidingWindow(100);
    
    // Ошибки
    private final Map<String, AtomicInteger> errorCounts = new ConcurrentHashMap<>();
    
    private final ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor();
    private volatile boolean isCollecting = true;
    
    private metrics() {
        startCollection();
    }
    
    public static metrics getInstance() {
        if (instance == null) {
            synchronized (lock) {
                if (instance == null) {
                    instance = new metrics();
                }
            }
        }
        return instance;
    }
    
    /**
     * Метрики для одного метода
     */
    public static class MethodMetrics {
        private final AtomicLong total = new AtomicLong(0);
        private final AtomicLong success = new AtomicLong(0);
        private final AtomicLong failed = new AtomicLong(0);
        private final AtomicLong totalLatency = new AtomicLong(0);
        private final AtomicLong minLatency = new AtomicLong(Long.MAX_VALUE);
        private final AtomicLong maxLatency = new AtomicLong(0);
        
        public void record(boolean success, long latencyMs) {
            total.incrementAndGet();
            totalLatency.addAndGet(latencyMs);
            
            if (success) {
                this.success.incrementAndGet();
            } else {
                this.failed.incrementAndGet();
            }
            
            minLatency.updateAndGet(min -> Math.min(min, latencyMs));
            maxLatency.updateAndGet(max -> Math.max(max, latencyMs));
        }
        
        public long getTotal() { return total.get(); }
        public long getSuccess() { return success.get(); }
        public long getFailed() { return failed.get(); }
        public double getAvgLatency() {
            long t = total.get();
            return t > 0 ? totalLatency.get() / (double) t : 0;
        }
        public long getMinLatency() {
            long min = minLatency.get();
            return min == Long.MAX_VALUE ? 0 : min;
        }
        public long getMaxLatency() { return maxLatency.get(); }
        public double getSuccessRate() {
            long t = total.get();
            return t > 0 ? (success.get() * 100.0 / t) : 0;
        }
        
        public Map<String, Object> toMap() {
            Map<String, Object> map = new HashMap<>();
            map.put("total", getTotal());
            map.put("success", getSuccess());
            map.put("failed", getFailed());
            map.put("avg_latency_ms", getAvgLatency());
            map.put("min_latency_ms", getMinLatency());
            map.put("max_latency_ms", getMaxLatency());
            map.put("success_rate", getSuccessRate());
            return map;
        }
    }
    
    /**
     * Скользящее окно для истории запросов
     */
    private static class SlidingWindow {
        private final int maxSize;
        private final ConcurrentLinkedQueue<RequestRecord> records = new ConcurrentLinkedQueue<>();
        
        SlidingWindow(int maxSize) {
            this.maxSize = maxSize;
        }
        
        void add(RequestRecord record) {
            records.add(record);
            while (records.size() > maxSize) {
                records.poll();
            }
        }
        
        long getRequestsInLastSeconds(int seconds) {
            long cutoff = System.currentTimeMillis() - (seconds * 1000);
            return records.stream()
                    .filter(r -> r.timestamp >= cutoff)
                    .count();
        }
        
        long getErrorsInLastSeconds(int seconds) {
            long cutoff = System.currentTimeMillis() - (seconds * 1000);
            return records.stream()
                    .filter(r -> r.timestamp >= cutoff && !r.success)
                    .count();
        }
        
        private static class RequestRecord {
            final long timestamp;
            final boolean success;
            final String method;
            final long latencyMs;
            
            RequestRecord(boolean success, String method, long latencyMs) {
                this.timestamp = System.currentTimeMillis();
                this.success = success;
                this.method = method;
                this.latencyMs = latencyMs;
            }
        }
    }
    
    private void startCollection() {
        scheduler.scheduleAtFixedRate(() -> {
            if (isCollecting) {
                logMetrics();
            }
        }, 0, 30, TimeUnit.SECONDS);
    }
    
    private void logMetrics() {
        if (logger.isLoggable(Level.INFO)) {
            logger.info(getMetricsSummary());
        }
    }
    
    /**
     * Записать результат запроса
     */
    public void recordRequest(String method, long latencyMs, boolean success, String error) {
        totalRequests.incrementAndGet();
        totalLatency.addAndGet(latencyMs);
        
        if (success) {
            successfulRequests.incrementAndGet();
        } else {
            failedRequests.incrementAndGet();
            if (error != null) {
                recordError(error);
            }
        }
        
        // Записываем по методу
        methodMetrics.computeIfAbsent(method, k -> new MethodMetrics())
                .record(success, latencyMs);
        
        // Добавляем в историю
        requestHistory.add(new SlidingWindow.RequestRecord(success, method, latencyMs));
        
        if (logger.isLoggable(Level.FINE)) {
            logger.fine(String.format("Request: %s, success=%s, latency=%dms", 
                method, success, latencyMs));
        }
    }
    
    /**
     * Записать ошибку
     */
    public void recordError(String errorType) {
        errorCounts.computeIfAbsent(errorType, k -> new AtomicInteger(0))
                .incrementAndGet();
    }
    
    /**
     * Записать событие подключения
     */
    public void recordConnectionEvent(boolean connected, long durationMs) {
        this.isConnected = connected;
        if (connected) {
            lastConnectionTime = System.currentTimeMillis();
        }
    }
    
    /**
     * Записать попытку переподключения
     */
    public void recordReconnectAttempt(boolean success) {
        reconnectAttempts.incrementAndGet();
        if (success) {
            reconnectSuccess.incrementAndGet();
        } else {
            reconnectFailures.incrementAndGet();
        }
    }
    
    /**
     * Получить текущую статистику
     */
    public Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        long total = totalRequests.get();
        
        stats.put("total_requests", total);
        stats.put("successful_requests", successfulRequests.get());
        stats.put("failed_requests", failedRequests.get());
        stats.put("success_rate", total > 0 ? (successfulRequests.get() * 100.0 / total) : 0);
        stats.put("avg_latency_ms", total > 0 ? totalLatency.get() / (double) total : 0);
        
        // За последние 60 секунд
        long requestsLastMin = requestHistory.getRequestsInLastSeconds(60);
        stats.put("requests_last_60s", requestsLastMin);
        stats.put("errors_last_60s", requestHistory.getErrorsInLastSeconds(60));
        
        // Соединение
        stats.put("is_connected", isConnected);
        stats.put("last_connection_time", lastConnectionTime);
        stats.put("reconnect_attempts", reconnectAttempts.get());
        stats.put("reconnect_success", reconnectSuccess.get());
        stats.put("reconnect_failures", reconnectFailures.get());
        stats.put("reconnect_success_rate", reconnectAttempts.get() > 0 
            ? (reconnectSuccess.get() * 100.0 / reconnectAttempts.get()) : 0);
        
        // Методы
        Map<String, Object> methods = new HashMap<>();
        methodMetrics.forEach((name, mm) -> methods.put(name, mm.toMap()));
        stats.put("methods", methods);
        
        // Ошибки
        Map<String, Integer> errors = new HashMap<>();
        errorCounts.forEach((type, count) -> errors.put(type, count.get()));
        stats.put("errors", errors);
        
        return stats;
    }
    
    /**
     * Получить текстовую сводку
     */
    public String getMetricsSummary() {
        StringBuilder sb = new StringBuilder();
        sb.append("\n=== Client Metrics ===\n");
        
        long total = totalRequests.get();
        long success = successfulRequests.get();
        long failed = failedRequests.get();
        
        sb.append(String.format("\n📊 Request Statistics:\n"));
        sb.append(String.format("  Total: %d\n", total));
        sb.append(String.format("  Successful: %d (%.1f%%)\n", success,
            total > 0 ? (success * 100.0 / total) : 0));
        sb.append(String.format("  Failed: %d (%.1f%%)\n", failed,
            total > 0 ? (failed * 100.0 / total) : 0));
        sb.append(String.format("  Avg Latency: %.2f ms\n",
            total > 0 ? totalLatency.get() / (double) total : 0));
        
        sb.append(String.format("\n🔌 Connection:\n"));
        sb.append(String.format("  Status: %s\n", isConnected ? "✅ Connected" : "❌ Disconnected"));
        sb.append(String.format("  Reconnect attempts: %d\n", reconnectAttempts.get()));
        sb.append(String.format("  Reconnect success: %d\n", reconnectSuccess.get()));
        
        sb.append(String.format("\n⏱️ Last 60 seconds:\n"));
        sb.append(String.format("  Requests: %d\n", requestHistory.getRequestsInLastSeconds(60)));
        sb.append(String.format("  Errors: %d\n", requestHistory.getErrorsInLastSeconds(60)));
        
        // Топ методов
        if (!methodMetrics.isEmpty()) {
            sb.append("\n📈 Top Methods:\n");
            methodMetrics.entrySet().stream()
                    .sorted((a, b) -> Long.compare(b.getValue().getTotal(), a.getValue().getTotal()))
                    .limit(5)
                    .forEach(e -> {
                        MethodMetrics mm = e.getValue();
                        sb.append(String.format("  %s: %d req, %.1f%% success, %.0fms avg\n",
                            e.getKey(), mm.getTotal(), mm.getSuccessRate(), mm.getAvgLatency()));
                    });
        }
        
        // Ошибки
        if (!errorCounts.isEmpty()) {
            sb.append("\n⚠️ Recent Errors:\n");
            errorCounts.entrySet().stream()
                    .sorted((a, b) -> Integer.compare(b.getValue().get(), a.getValue().get()))
                    .limit(5)
                    .forEach(e -> sb.append(String.format("  %s: %d\n", e.getKey(), e.getValue().get())));
        }
        
        return sb.toString();
    }
    
    /**
     * Сбросить все метрики
     */
    public void reset() {
        totalRequests.set(0);
        successfulRequests.set(0);
        failedRequests.set(0);
        totalLatency.set(0);
        reconnectAttempts.set(0);
        reconnectSuccess.set(0);
        reconnectFailures.set(0);
        methodMetrics.clear();
        errorCounts.clear();
        requestHistory.records.clear();
        
        logger.info("Client metrics reset");
    }
    
    /**
     * Получить метрики в формате Prometheus
     */
    public String getPrometheusFormat() {
        StringBuilder sb = new StringBuilder();
        long total = totalRequests.get();
        
        sb.append("# HELP client_requests_total Total requests from client\n");
        sb.append("# TYPE client_requests_total counter\n");
        sb.append("client_requests_total ").append(total).append("\n");
        
        sb.append("# HELP client_requests_successful Total successful requests\n");
        sb.append("# TYPE client_requests_successful counter\n");
        sb.append("client_requests_successful ").append(successfulRequests.get()).append("\n");
        
        sb.append("# HELP client_requests_failed Total failed requests\n");
        sb.append("# TYPE client_requests_failed counter\n");
        sb.append("client_requests_failed ").append(failedRequests.get()).append("\n");
        
        sb.append("# HELP client_avg_latency_ms Average request latency\n");
        sb.append("# TYPE client_avg_latency_ms gauge\n");
        sb.append("client_avg_latency_ms ")
            .append(total > 0 ? totalLatency.get() / (double) total : 0).append("\n");
        
        sb.append("# HELP client_connected Connection status\n");
        sb.append("# TYPE client_connected gauge\n");
        sb.append("client_connected ").append(isConnected ? 1 : 0).append("\n");
        
        sb.append("# HELP client_reconnect_attempts Total reconnect attempts\n");
        sb.append("# TYPE client_reconnect_attempts counter\n");
        sb.append("client_reconnect_attempts ").append(reconnectAttempts.get()).append("\n");
        
        // Метрики по методам
        methodMetrics.forEach((method, mm) -> {
            String safeMethod = method.replace('.', '_').replace('-', '_');
            sb.append("# HELP client_method_").append(safeMethod).append("_total Total calls to ").append(method).append("\n");
            sb.append("# TYPE client_method_").append(safeMethod).append("_total counter\n");
            sb.append("client_method_").append(safeMethod).append("_total ").append(mm.getTotal()).append("\n");
            
            sb.append("# HELP client_method_").append(safeMethod).append("_avg_ms Average latency for ").append(method).append("\n");
            sb.append("# TYPE client_method_").append(safeMethod).append("_avg_ms gauge\n");
            sb.append("client_method_").append(safeMethod).append("_avg_ms ").append(mm.getAvgLatency()).append("\n");
        });
        
        return sb.toString();
    }
    
    /**
     * Остановить сбор метрик
     */
    public void stop() {
        isCollecting = false;
        scheduler.shutdown();
        try {
            if (!scheduler.awaitTermination(5, TimeUnit.SECONDS)) {
                scheduler.shutdownNow();
            }
        } catch (InterruptedException e) {
            scheduler.shutdownNow();
            Thread.currentThread().interrupt();
        }
        logger.info("Client metrics collection stopped");
    }
}