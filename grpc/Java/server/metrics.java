package com.bot.grpc.server;

import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.Map;
import java.util.HashMap;
import java.util.logging.Logger;
import java.util.logging.Level;
import java.time.Instant;
import java.time.Duration;

/**
 * Metrics collection and monitoring system for gRPC server
 */
public class metrics {
    private static final Logger logger = Logger.getLogger(metrics.class.getName());
    
    // Singleton instance
    private static volatile metrics instance;
    private static final Object lock = new Object();
    
    // Metric categories
    private final Map<String, Counter> counters;
    private final Map<String, Timer> timers;
    private final Map<String, Gauge> gauges;
    private final Map<String, Histogram> histograms;
    
    // Connection pool metrics
    private final AtomicInteger activeConnections;
    private final AtomicInteger totalConnections;
    private final AtomicLong connectionCreationTime;
    private final AtomicLong connectionWaitTime;
    
    // Request metrics
    private final AtomicLong totalRequests;
    private final AtomicLong successfulRequests;
    private final AtomicLong failedRequests;
    private final AtomicLong requestLatency;
    
    // Music service specific metrics
    private final AtomicInteger activeMusicSessions;
    private final AtomicLong totalMusicPlaybacks;
    private final AtomicLong totalMusicDuration;
    private final AtomicInteger currentQueueSize;
    
    // System metrics
    private final AtomicLong memoryUsage;
    private final AtomicLong cpuUsage;
    private final AtomicInteger threadCount;
    
    // Error tracking
    private final Map<String, AtomicInteger> errorCounts;
    
    // Metric collection configuration
    private final ScheduledExecutorService scheduler;
    private volatile boolean isCollecting;
    
    /**
     * Counter metric for incrementing values
     */
    public static class Counter {
        private final AtomicLong value;
        private final String name;
        
        Counter(String name) {
            this.name = name;
            this.value = new AtomicLong(0);
        }
        
        public void increment() {
            value.incrementAndGet();
        }
        
        public void increment(long delta) {
            value.addAndGet(delta);
        }
        
        public void decrement() {
            value.decrementAndGet();
        }
        
        public long getValue() {
            return value.get();
        }
        
        public void reset() {
            value.set(0);
        }
        
        @Override
        public String toString() {
            return String.format("%s: %d", name, value.get());
        }
    }
    
    /**
     * Timer metric for measuring durations
     */
    public static class Timer {
        private final AtomicLong totalTime;
        private final AtomicLong count;
        private final String name;
        
        Timer(String name) {
            this.name = name;
            this.totalTime = new AtomicLong(0);
            this.count = new AtomicLong(0);
        }
        
        public TimerContext start() {
            return new TimerContext(this);
        }
        
        public void record(long durationMs) {
            totalTime.addAndGet(durationMs);
            count.incrementAndGet();
        }
        
        public double getAverageMs() {
            long c = count.get();
            return c > 0 ? totalTime.get() / (double) c : 0.0;
        }
        
        public long getTotalTimeMs() {
            return totalTime.get();
        }
        
        public long getCount() {
            return count.get();
        }
        
        public static class TimerContext implements AutoCloseable {
            private final Timer timer;
            private final long startTime;
            
            TimerContext(Timer timer) {
                this.timer = timer;
                this.startTime = System.nanoTime();
            }
            
            public void stop() {
                long durationNs = System.nanoTime() - startTime;
                timer.record(durationNs / 1_000_000);
            }
            
            @Override
            public void close() {
                stop();
            }
        }
    }
    
    /**
     * Gauge metric for point-in-time values
     */
    public static class Gauge {
        private final AtomicLong value;
        private final String name;
        
        Gauge(String name) {
            this.name = name;
            this.value = new AtomicLong(0);
        }
        
        public void set(long value) {
            this.value.set(value);
        }
        
        public long getValue() {
            return value.get();
        }
    }
    
    /**
     * Histogram metric for distribution of values
     */
    public static class Histogram {
        private final String name;
        private final long[] buckets;
        private final AtomicLong[] bucketCounts;
        private final AtomicLong totalSum;
        private final AtomicLong count;
        
        public Histogram(String name, long... buckets) {
            this.name = name;
            this.buckets = buckets;
            this.bucketCounts = new AtomicLong[buckets.length + 1];
            for (int i = 0; i < bucketCounts.length; i++) {
                bucketCounts[i] = new AtomicLong(0);
            }
            this.totalSum = new AtomicLong(0);
            this.count = new AtomicLong(0);
        }
        
        public void record(long value) {
            count.incrementAndGet();
            totalSum.addAndGet(value);
            
            // Find appropriate bucket
            int bucketIndex = bucketCounts.length - 1;
            for (int i = 0; i < buckets.length; i++) {
                if (value <= buckets[i]) {
                    bucketIndex = i;
                    break;
                }
            }
            bucketCounts[bucketIndex].incrementAndGet();
        }
        
        public long getCount() {
            return count.get();
        }
        
        public double getAverage() {
            long c = count.get();
            return c > 0 ? totalSum.get() / (double) c : 0.0;
        }
        
        public long getTotalSum() {
            return totalSum.get();
        }
        
        public Map<String, Long> getPercentiles() {
            // Calculate approximate percentiles
            Map<String, Long> percentiles = new HashMap<>();
            long total = count.get();
            if (total == 0) return percentiles;
            
            long[] cumulative = new long[bucketCounts.length];
            long sum = 0;
            for (int i = 0; i < bucketCounts.length; i++) {
                sum += bucketCounts[i].get();
                cumulative[i] = sum;
            }
            
            // Calculate p50, p95, p99
            percentiles.put("p50", findPercentile(cumulative, total, 0.50));
            percentiles.put("p95", findPercentile(cumulative, total, 0.95));
            percentiles.put("p99", findPercentile(cumulative, total, 0.99));
            percentiles.put("p999", findPercentile(cumulative, total, 0.999));
            
            return percentiles;
        }
        
        private long findPercentile(long[] cumulative, long total, double percentile) {
            long target = (long) (total * percentile);
            for (int i = 0; i < cumulative.length; i++) {
                if (cumulative[i] >= target) {
                    if (i < buckets.length) {
                        return buckets[i];
                    } else {
                        return Long.MAX_VALUE;
                    }
                }
            }
            return Long.MAX_VALUE;
        }
    }
    
    private metrics() {
        this.counters = new ConcurrentHashMap<>();
        this.timers = new ConcurrentHashMap<>();
        this.gauges = new ConcurrentHashMap<>();
        this.histograms = new ConcurrentHashMap<>();
        this.errorCounts = new ConcurrentHashMap<>();
        
        // Connection pool metrics
        this.activeConnections = new AtomicInteger(0);
        this.totalConnections = new AtomicInteger(0);
        this.connectionCreationTime = new AtomicLong(0);
        this.connectionWaitTime = new AtomicLong(0);
        
        // Request metrics
        this.totalRequests = new AtomicLong(0);
        this.successfulRequests = new AtomicLong(0);
        this.failedRequests = new AtomicLong(0);
        this.requestLatency = new AtomicLong(0);
        
        // Music metrics
        this.activeMusicSessions = new AtomicInteger(0);
        this.totalMusicPlaybacks = new AtomicLong(0);
        this.totalMusicDuration = new AtomicLong(0);
        this.currentQueueSize = new AtomicInteger(0);
        
        // System metrics
        this.memoryUsage = new AtomicLong(0);
        this.cpuUsage = new AtomicLong(0);
        this.threadCount = new AtomicInteger(0);
        
        this.scheduler = Executors.newScheduledThreadPool(1);
        this.isCollecting = true;
        
        initializeDefaultMetrics();
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
    
    private void initializeDefaultMetrics() {
        // Create default counters
        registerCounter("requests.total");
        registerCounter("requests.success");
        registerCounter("requests.failed");
        registerCounter("connections.active");
        registerCounter("connections.total");
        registerCounter("music.playbacks");
        registerCounter("music.sessions.active");
        
        // Create default timers
        registerTimer("request.latency");
        registerTimer("connection.creation");
        registerTimer("music.playback.duration");
        
        // Create default histograms
        registerHistogram("request.size", 1024, 10240, 102400, 1048576);
        registerHistogram("response.size", 1024, 10240, 102400, 1048576);
        registerHistogram("queue.size", 1, 5, 10, 25, 50, 100);
    }
    
    private void startCollection() {
        scheduler.scheduleAtFixedRate(() -> {
            if (isCollecting) {
                collectSystemMetrics();
                logMetrics();
            }
        }, 0, 30, TimeUnit.SECONDS);
    }
    
    private void collectSystemMetrics() {
        // Collect memory metrics
        Runtime runtime = Runtime.getRuntime();
        long usedMemory = runtime.totalMemory() - runtime.freeMemory();
        memoryUsage.set(usedMemory);
        
        // Collect thread metrics
        threadCount.set(Thread.activeCount());
        
        // Update gauges
        Gauge memoryGauge = getGauge("system.memory.used");
        if (memoryGauge != null) memoryGauge.set(usedMemory);
        
        Gauge threadGauge = getGauge("system.threads");
        if (threadGauge != null) threadGauge.set(threadCount.get());
    }
    
    private void logMetrics() {
        if (logger.isLoggable(Level.INFO)) {
            logger.info(getMetricsSummary());
        }
    }
    
    /**
     * Register a counter metric
     */
    public void registerCounter(String name) {
        counters.putIfAbsent(name, new Counter(name));
    }
    
    /**
     * Register a timer metric
     */
    public void registerTimer(String name) {
        timers.putIfAbsent(name, new Timer(name));
    }
    
    /**
     * Register a gauge metric
     */
    public void registerGauge(String name) {
        gauges.putIfAbsent(name, new Gauge(name));
    }
    
    /**
     * Register a histogram metric
     */
    public void registerHistogram(String name, long... buckets) {
        histograms.putIfAbsent(name, new Histogram(name, buckets));
    }
    
    /**
     * Get a counter by name
     */
    public Counter getCounter(String name) {
        return counters.get(name);
    }
    
    /**
     * Get a timer by name
     */
    public Timer getTimer(String name) {
        return timers.get(name);
    }
    
    /**
     * Get a gauge by name
     */
    public Gauge getGauge(String name) {
        return gauges.get(name);
    }
    
    /**
     * Get a histogram by name
     */
    public Histogram getHistogram(String name) {
        return histograms.get(name);
    }
    
    /**
     * Increment a counter
     */
    public void incrementCounter(String name) {
        Counter counter = counters.get(name);
        if (counter != null) {
            counter.increment();
        }
    }
    
    /**
     * Increment a counter by delta
     */
    public void incrementCounter(String name, long delta) {
        Counter counter = counters.get(name);
        if (counter != null) {
            counter.increment(delta);
        }
    }
    
    /**
     * Record error occurrence
     */
    public void recordError(String errorType) {
        errorCounts.computeIfAbsent(errorType, k -> new AtomicInteger(0))
                   .incrementAndGet();
        incrementCounter("errors.total");
    }
    
    /**
     * Record request metrics
     */
    public void recordRequest(boolean success, long latencyMs) {
        totalRequests.incrementAndGet();
        requestLatency.addAndGet(latencyMs);
        
        if (success) {
            successfulRequests.incrementAndGet();
            incrementCounter("requests.success");
        } else {
            failedRequests.incrementAndGet();
            incrementCounter("requests.failed");
        }
        
        Timer timer = getTimer("request.latency");
        if (timer != null) {
            timer.record(latencyMs);
        }
    }
    
    /**
     * Record connection pool metrics
     */
    public void recordConnectionCreated() {
        totalConnections.incrementAndGet();
        activeConnections.incrementAndGet();
        incrementCounter("connections.total");
        incrementCounter("connections.active");
    }
    
    public void recordConnectionClosed() {
        activeConnections.decrementAndGet();
        incrementCounter("connections.active", -1);
    }
    
    public void recordConnectionCreationTime(long durationMs) {
        connectionCreationTime.addAndGet(durationMs);
        Timer timer = getTimer("connection.creation");
        if (timer != null) {
            timer.record(durationMs);
        }
    }
    
    public void recordConnectionWaitTime(long durationMs) {
        connectionWaitTime.addAndGet(durationMs);
    }
    
    /**
     * Record music playback metrics
     */
    public void recordMusicPlayback(long durationMs) {
        totalMusicPlaybacks.incrementAndGet();
        totalMusicDuration.addAndGet(durationMs);
        incrementCounter("music.playbacks");
        
        Timer timer = getTimer("music.playback.duration");
        if (timer != null) {
            timer.record(durationMs);
        }
    }
    
    public void recordMusicSessionStarted() {
        activeMusicSessions.incrementAndGet();
        incrementCounter("music.sessions.active");
    }
    
    public void recordMusicSessionEnded() {
        activeMusicSessions.decrementAndGet();
        incrementCounter("music.sessions.active", -1);
    }
    
    public void updateQueueSize(int size) {
        currentQueueSize.set(size);
        Histogram histogram = getHistogram("queue.size");
        if (histogram != null) {
            histogram.record(size);
        }
    }
    
    /**
     * Get comprehensive metrics summary
     */
    public String getMetricsSummary() {
        StringBuilder sb = new StringBuilder();
        sb.append("\n=== Metrics Summary ===\n");
        
        // Request statistics
        long total = totalRequests.get();
        long success = successfulRequests.get();
        long failed = failedRequests.get();
        double successRate = total > 0 ? (success * 100.0 / total) : 0.0;
        
        sb.append(String.format("\n📊 Request Statistics:\n"));
        sb.append(String.format("  Total Requests: %d\n", total));
        sb.append(String.format("  Successful: %d (%.2f%%)\n", success, successRate));
        sb.append(String.format("  Failed: %d\n", failed));
        sb.append(String.format("  Avg Latency: %.2f ms\n", 
            total > 0 ? requestLatency.get() / (double) total : 0));
        
        // Connection pool statistics
        sb.append(String.format("\n🔌 Connection Pool:\n"));
        sb.append(String.format("  Active: %d\n", activeConnections.get()));
        sb.append(String.format("  Total Created: %d\n", totalConnections.get()));
        sb.append(String.format("  Avg Creation Time: %.2f ms\n",
            totalConnections.get() > 0 ? connectionCreationTime.get() / (double) totalConnections.get() : 0));
        
        // Music service statistics
        sb.append(String.format("\n🎵 Music Service:\n"));
        sb.append(String.format("  Active Sessions: %d\n", activeMusicSessions.get()));
        sb.append(String.format("  Total Playbacks: %d\n", totalMusicPlaybacks.get()));
        sb.append(String.format("  Total Duration: %s\n", formatDuration(totalMusicDuration.get())));
        sb.append(String.format("  Current Queue Size: %d\n", currentQueueSize.get()));
        
        // System statistics
        sb.append(String.format("\n💻 System:\n"));
        sb.append(String.format("  Memory Usage: %s\n", formatBytes(memoryUsage.get())));
        sb.append(String.format("  Active Threads: %d\n", threadCount.get()));
        
        // Error statistics
        if (!errorCounts.isEmpty()) {
            sb.append(String.format("\n⚠️ Error Statistics:\n"));
            errorCounts.forEach((type, count) -> {
                sb.append(String.format("  %s: %d\n", type, count.get()));
            });
        }
        
        // Timer metrics
        if (!timers.isEmpty()) {
            sb.append(String.format("\n⏱️ Timer Metrics:\n"));
            timers.forEach((name, timer) -> {
                sb.append(String.format("  %s: avg=%.2f ms, count=%d\n", 
                    name, timer.getAverageMs(), timer.getCount()));
            });
        }
        
        // Histogram metrics
        if (!histograms.isEmpty()) {
            sb.append(String.format("\n📈 Histogram Metrics:\n"));
            histograms.forEach((name, histogram) -> {
                if (histogram.getCount() > 0) {
                    sb.append(String.format("  %s: avg=%.2f, p95=%d, p99=%d\n",
                        name, histogram.getAverage(),
                        histogram.getPercentiles().getOrDefault("p95", 0L),
                        histogram.getPercentiles().getOrDefault("p99", 0L)));
                }
            });
        }
        
        return sb.toString();
    }
    
    /**
     * Get metrics in JSON format for external monitoring
     */
    public String getMetricsJson() {
        StringBuilder json = new StringBuilder();
        json.append("{");
        
        // Request metrics
        json.append("\"requests\":{");
        json.append("\"total\":").append(totalRequests.get()).append(",");
        json.append("\"successful\":").append(successfulRequests.get()).append(",");
        json.append("\"failed\":").append(failedRequests.get()).append(",");
        json.append("\"avgLatencyMs\":").append(
            totalRequests.get() > 0 ? requestLatency.get() / (double) totalRequests.get() : 0);
        json.append("},");
        
        // Connection metrics
        json.append("\"connections\":{");
        json.append("\"active\":").append(activeConnections.get()).append(",");
        json.append("\"total\":").append(totalConnections.get());
        json.append("},");
        
        // Music metrics
        json.append("\"music\":{");
        json.append("\"activeSessions\":").append(activeMusicSessions.get()).append(",");
        json.append("\"totalPlaybacks\":").append(totalMusicPlaybacks.get()).append(",");
        json.append("\"totalDurationMs\":").append(totalMusicDuration.get());
        json.append("},");
        
        // System metrics
        json.append("\"system\":{");
        json.append("\"memoryBytes\":").append(memoryUsage.get()).append(",");
        json.append("\"threads\":").append(threadCount.get());
        json.append("}");
        
        json.append("}");
        return json.toString();
    }
    
    /**
     * Reset all metrics
     */
    public void reset() {
        totalRequests.set(0);
        successfulRequests.set(0);
        failedRequests.set(0);
        requestLatency.set(0);
        activeConnections.set(0);
        totalConnections.set(0);
        connectionCreationTime.set(0);
        connectionWaitTime.set(0);
        activeMusicSessions.set(0);
        totalMusicPlaybacks.set(0);
        totalMusicDuration.set(0);
        currentQueueSize.set(0);
        
        counters.values().forEach(Counter::reset);
        errorCounts.clear();
        
        logger.info("All metrics have been reset");
    }
    
    /**
     * Stop metrics collection
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
        logger.info("Metrics collection stopped");
    }
    
    private String formatDuration(long ms) {
        long seconds = ms / 1000;
        long minutes = seconds / 60;
        long hours = minutes / 60;
        
        if (hours > 0) {
            return String.format("%dh %dm %ds", hours, minutes % 60, seconds % 60);
        } else if (minutes > 0) {
            return String.format("%dm %ds", minutes, seconds % 60);
        } else {
            return String.format("%ds", seconds);
        }
    }
    
    private String formatBytes(long bytes) {
        if (bytes < 1024) return bytes + " B";
        int exp = (int) (Math.log(bytes) / Math.log(1024));
        String pre = "KMGTPE".charAt(exp - 1) + "";
        return String.format("%.2f %sB", bytes / Math.pow(1024, exp), pre);
    }
    
    /**
     * Simple metrics endpoint for HTTP monitoring (if you have an HTTP server)
     */
    public String getPrometheusFormat() {
        StringBuilder sb = new StringBuilder();
        
        // Request metrics
        sb.append("# HELP requests_total Total number of requests\n");
        sb.append("# TYPE requests_total counter\n");
        sb.append("requests_total ").append(totalRequests.get()).append("\n");
        
        sb.append("# HELP requests_successful Total successful requests\n");
        sb.append("# TYPE requests_successful counter\n");
        sb.append("requests_successful ").append(successfulRequests.get()).append("\n");
        
        sb.append("# HELP requests_failed Total failed requests\n");
        sb.append("# TYPE requests_failed counter\n");
        sb.append("requests_failed ").append(failedRequests.get()).append("\n");
        
        // Connection metrics
        sb.append("# HELP connections_active Active connections\n");
        sb.append("# TYPE connections_active gauge\n");
        sb.append("connections_active ").append(activeConnections.get()).append("\n");
        
        // Music metrics
        sb.append("# HELP music_sessions_active Active music sessions\n");
        sb.append("# TYPE music_sessions_active gauge\n");
        sb.append("music_sessions_active ").append(activeMusicSessions.get()).append("\n");
        
        sb.append("# HELP music_playbacks_total Total music playbacks\n");
        sb.append("# TYPE music_playbacks_total counter\n");
        sb.append("music_playbacks_total ").append(totalMusicPlaybacks.get()).append("\n");
        
        // System metrics
        sb.append("# HELP system_memory_bytes Memory usage in bytes\n");
        sb.append("# TYPE system_memory_bytes gauge\n");
        sb.append("system_memory_bytes ").append(memoryUsage.get()).append("\n");
        
        sb.append("# HELP system_threads Number of active threads\n");
        sb.append("# TYPE system_threads gauge\n");
        sb.append("system_threads ").append(threadCount.get()).append("\n");
        
        return sb.toString();
    }
}