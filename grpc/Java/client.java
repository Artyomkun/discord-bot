package com.bot.grpc;

import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.StatusRuntimeException;
import org.springframework.stereotype.Component;
import javax.annotation.PreDestroy;
import java.util.concurrent.TimeUnit;
import java.util.logging.Logger;

// Импорты для метрик
import com.bot.grpc.client.metrics;
import com.bot.grpc.client.metrics.MethodMetrics;

@Component
public class client {
    private static final Logger logger = Logger.getLogger(client.class.getName());
    
    // Каналы для разных сервисов
    private ManagedChannel goChannel;
    private ManagedChannel elixirChannel;
    private ManagedChannel pythonChannel;
    
    // Stubs
    private AudioServiceGrpc.AudioServiceBlockingStub goStub;
    private AudioServiceGrpc.AudioServiceBlockingStub elixirStub;
    private DiscordClientServiceGrpc.DiscordClientServiceBlockingStub pythonStub;
    
    // Метрики
    private final metrics clientMetrics;
    
    public client() {
        // Инициализируем метрики
        this.clientMetrics = metrics.getInstance();
        
        // Go процессор (порт 8082)
        this.goChannel = ManagedChannelBuilder.forAddress("localhost", 8082)
                .usePlaintext()
                .keepAliveTime(30, TimeUnit.SECONDS)
                .keepAliveTimeout(10, TimeUnit.SECONDS)
                .maxInboundMessageSize(100 * 1024 * 1024)
                .build();
        this.goStub = AudioServiceGrpc.newBlockingStub(goChannel);
        
        // Elixir (порт 4000)
        this.elixirChannel = ManagedChannelBuilder.forAddress("localhost", 4000)
                .usePlaintext()
                .keepAliveTime(30, TimeUnit.SECONDS)
                .keepAliveTimeout(10, TimeUnit.SECONDS)
                .maxInboundMessageSize(100 * 1024 * 1024)
                .build();
        this.elixirStub = AudioServiceGrpc.newBlockingStub(elixirChannel);
        
        // Python бот (порт 50052)
        this.pythonChannel = ManagedChannelBuilder.forAddress("localhost", 50052)
                .usePlaintext()
                .keepAliveTime(30, TimeUnit.SECONDS)
                .keepAliveTimeout(10, TimeUnit.SECONDS)
                .maxInboundMessageSize(100 * 1024 * 1024)
                .build();
        this.pythonStub = DiscordClientServiceGrpc.newBlockingStub(pythonChannel);
        
        logger.info("✅ gRPC клиенты подключены (Go:8082, Elixir:4000, Python:50052)");
        logger.info("📊 Клиентские метрики активированы");
    }
    
    // ========== ВСПОМОГАТЕЛЬНЫЙ МЕТОД ДЛЯ ЗАПИСИ МЕТРИК ==========
    
    private <T> T executeWithMetrics(String method, String service, 
                                      java.util.function.Supplier<T> operation) {
        long startTime = System.currentTimeMillis();
        try {
            T result = operation.get();
            long duration = System.currentTimeMillis() - startTime;
            clientMetrics.recordRequest(method + ":" + service, duration, true, null);
            return result;
        } catch (StatusRuntimeException e) {
            long duration = System.currentTimeMillis() - startTime;
            String error = e.getStatus().getCode().toString();
            clientMetrics.recordRequest(method + ":" + service, duration, false, error);
            clientMetrics.recordError(error);
            logger.warning(String.format("gRPC error in %s:%s - %s", service, method, error));
            throw e;
        } catch (Exception e) {
            long duration = System.currentTimeMillis() - startTime;
            String error = e.getClass().getSimpleName() + ": " + e.getMessage();
            clientMetrics.recordRequest(method + ":" + service, duration, false, error);
            clientMetrics.recordError(e.getClass().getSimpleName());
            logger.severe(String.format("Error in %s:%s - %s", service, method, e.getMessage()));
            throw e;
        }
    }
    
    // ========== GO МЕТОДЫ ==========
    
    public AudioServiceProto.PlayResponse playInGo(AudioServiceProto.PlayRequest request) {
        return executeWithMetrics("play", "go", () -> goStub.play(request));
    }
    
    public AudioServiceProto.StatusResponse getStatusFromGo(AudioServiceProto.StatusRequest request) {
        return executeWithMetrics("getStatus", "go", () -> goStub.getStatus(request));
    }
    
    public AudioServiceProto.EffectsResponse applyEffectsInGo(AudioServiceProto.EffectsRequest request) {
        return executeWithMetrics("applyEffects", "go", () -> goStub.applyEffects(request));
    }
    
    public AudioServiceProto.QueueResponse getQueueFromGo(AudioServiceProto.QueueRequest request) {
        return executeWithMetrics("getQueue", "go", () -> goStub.getQueue(request));
    }
    
    public AudioServiceProto.StopResponse stopInGo(AudioServiceProto.StopRequest request) {
        return executeWithMetrics("stop", "go", () -> goStub.stop(request));
    }
    
    public AudioServiceProto.PauseResponse pauseInGo(AudioServiceProto.PauseRequest request) {
        return executeWithMetrics("pause", "go", () -> goStub.pause(request));
    }
    
    public AudioServiceProto.ResumeResponse resumeInGo(AudioServiceProto.ResumeRequest request) {
        return executeWithMetrics("resume", "go", () -> goStub.resume(request));
    }
    
    public AudioServiceProto.VolumeResponse setVolumeInGo(AudioServiceProto.VolumeRequest request) {
        return executeWithMetrics("setVolume", "go", () -> goStub.volume(request));
    }
    
    public AudioServiceProto.SkipResponse skipInGo(AudioServiceProto.SkipRequest request) {
        return executeWithMetrics("skip", "go", () -> goStub.skip(request));
    }
    
    public boolean isGoHealthy() {
        long startTime = System.currentTimeMillis();
        try {
            AudioServiceProto.HealthRequest request = AudioServiceProto.HealthRequest.newBuilder().build();
            AudioServiceProto.HealthResponse response = goStub.healthCheck(request);
            long duration = System.currentTimeMillis() - startTime;
            clientMetrics.recordRequest("healthCheck:go", duration, true, null);
            return "healthy".equals(response.getStatus());
        } catch (Exception e) {
            long duration = System.currentTimeMillis() - startTime;
            clientMetrics.recordRequest("healthCheck:go", duration, false, e.getMessage());
            return false;
        }
    }
    
    // ========== ELIXIR МЕТОДЫ ==========
    
    public AudioServiceProto.PlayResponse playInElixir(AudioServiceProto.PlayRequest request) {
        return executeWithMetrics("play", "elixir", () -> elixirStub.play(request));
    }
    
    public AudioServiceProto.StatusResponse getStatusFromElixir(AudioServiceProto.StatusRequest request) {
        return executeWithMetrics("getStatus", "elixir", () -> elixirStub.getStatus(request));
    }
    
    public AudioServiceProto.EffectsResponse applyEffectsInElixir(AudioServiceProto.EffectsRequest request) {
        return executeWithMetrics("applyEffects", "elixir", () -> elixirStub.applyEffects(request));
    }
    
    public AudioServiceProto.QueueResponse getQueueFromElixir(AudioServiceProto.QueueRequest request) {
        return executeWithMetrics("getQueue", "elixir", () -> elixirStub.getQueue(request));
    }
    
    public AudioServiceProto.StopResponse stopInElixir(AudioServiceProto.StopRequest request) {
        return executeWithMetrics("stop", "elixir", () -> elixirStub.stop(request));
    }
    
    public AudioServiceProto.PauseResponse pauseInElixir(AudioServiceProto.PauseRequest request) {
        return executeWithMetrics("pause", "elixir", () -> elixirStub.pause(request));
    }
    
    public AudioServiceProto.ResumeResponse resumeInElixir(AudioServiceProto.ResumeRequest request) {
        return executeWithMetrics("resume", "elixir", () -> elixirStub.resume(request));
    }
    
    public AudioServiceProto.VolumeResponse setVolumeInElixir(AudioServiceProto.VolumeRequest request) {
        return executeWithMetrics("setVolume", "elixir", () -> elixirStub.volume(request));
    }
    
    public AudioServiceProto.SkipResponse skipInElixir(AudioServiceProto.SkipRequest request) {
        return executeWithMetrics("skip", "elixir", () -> elixirStub.skip(request));
    }
    
    public boolean isElixirHealthy() {
        long startTime = System.currentTimeMillis();
        try {
            AudioServiceProto.HealthRequest request = AudioServiceProto.HealthRequest.newBuilder().build();
            AudioServiceProto.HealthResponse response = elixirStub.healthCheck(request);
            long duration = System.currentTimeMillis() - startTime;
            clientMetrics.recordRequest("healthCheck:elixir", duration, true, null);
            return "healthy".equals(response.getStatus());
        } catch (Exception e) {
            long duration = System.currentTimeMillis() - startTime;
            clientMetrics.recordRequest("healthCheck:elixir", duration, false, e.getMessage());
            return false;
        }
    }
    
    // ========== PYTHON МЕТОДЫ ==========
    
    public DiscordClientProto.CommandResponse sendCommandToPython(DiscordClientProto.CommandRequest request) {
        return executeWithMetrics("sendCommand", "python", () -> pythonStub.sendCommand(request));
    }
    
    public DiscordClientProto.StatusResponse getStatusFromPython(DiscordClientProto.StatusRequest request) {
        return executeWithMetrics("getStatus", "python", () -> pythonStub.getStatus(request));
    }
    
    public DiscordClientProto.PlayResponse playInPython(DiscordClientProto.PlayRequest request) {
        return executeWithMetrics("play", "python", () -> pythonStub.play(request));
    }
    
    public DiscordClientProto.PauseResponse pauseInPython(DiscordClientProto.PauseRequest request) {
        return executeWithMetrics("pause", "python", () -> pythonStub.pause(request));
    }
    
    public DiscordClientProto.ResumeResponse resumeInPython(DiscordClientProto.ResumeRequest request) {
        return executeWithMetrics("resume", "python", () -> pythonStub.resume(request));
    }
    
    public DiscordClientProto.StopResponse stopInPython(DiscordClientProto.StopRequest request) {
        return executeWithMetrics("stop", "python", () -> pythonStub.stop(request));
    }
    
    public DiscordClientProto.SkipResponse skipInPython(DiscordClientProto.SkipRequest request) {
        return executeWithMetrics("skip", "python", () -> pythonStub.skip(request));
    }
    
    public DiscordClientProto.VolumeResponse setVolumeInPython(DiscordClientProto.VolumeRequest request) {
        return executeWithMetrics("setVolume", "python", () -> pythonStub.volume(request));
    }
    
    public DiscordClientProto.QueueResponse getQueueFromPython(DiscordClientProto.QueueRequest request) {
        return executeWithMetrics("getQueue", "python", () -> pythonStub.getQueue(request));
    }
    
    public DiscordClientProto.ClearQueueResponse clearQueueInPython(DiscordClientProto.ClearQueueRequest request) {
        return executeWithMetrics("clearQueue", "python", () -> pythonStub.clearQueue(request));
    }
    
    public DiscordClientProto.ShuffleQueueResponse shuffleQueueInPython(DiscordClientProto.ShuffleQueueRequest request) {
        return executeWithMetrics("shuffleQueue", "python", () -> pythonStub.shuffleQueue(request));
    }
    
    public DiscordClientProto.EffectsResponse applyEffectsInPython(DiscordClientProto.EffectsRequest request) {
        return executeWithMetrics("applyEffects", "python", () -> pythonStub.applyEffects(request));
    }
    
    public DiscordClientProto.GetEffectsResponse getEffectsFromPython(DiscordClientProto.GetEffectsRequest request) {
        return executeWithMetrics("getEffects", "python", () -> pythonStub.getEffects(request));
    }
    
    public DiscordClientProto.ResetEffectsResponse resetEffectsInPython(DiscordClientProto.ResetEffectsRequest request) {
        return executeWithMetrics("resetEffects", "python", () -> pythonStub.resetEffects(request));
    }
    
    public boolean isPythonHealthy() {
        long startTime = System.currentTimeMillis();
        try {
            DiscordClientProto.HealthRequest request = DiscordClientProto.HealthRequest.newBuilder().build();
            DiscordClientProto.HealthResponse response = pythonStub.healthCheck(request);
            long duration = System.currentTimeMillis() - startTime;
            clientMetrics.recordRequest("healthCheck:python", duration, true, null);
            return "healthy".equals(response.getStatus());
        } catch (Exception e) {
            long duration = System.currentTimeMillis() - startTime;
            clientMetrics.recordRequest("healthCheck:python", duration, false, e.getMessage());
            return false;
        }
    }
    
    // ========== МЕТОДЫ ДЛЯ ПОЛУЧЕНИЯ МЕТРИК ==========
    
    /**
     * Получить статистику клиента
     */
    public java.util.Map<String, Object> getClientStats() {
        return clientMetrics.getStats();
    }
    
    /**
     * Получить сводку метрик
     */
    public String getMetricsSummary() {
        return clientMetrics.getMetricsSummary();
    }
    
    /**
     * Получить метрики в формате Prometheus
     */
    public String getPrometheusMetrics() {
        return clientMetrics.getPrometheusFormat();
    }
    
    /**
     * Сбросить метрики
     */
    public void resetMetrics() {
        clientMetrics.reset();
        logger.info("Клиентские метрики сброшены");
    }
    
    /**
     * Записать событие подключения
     */
    public void recordConnectionEvent(boolean connected, long durationMs) {
        clientMetrics.recordConnectionEvent(connected, durationMs);
    }
    
    /**
     * Записать попытку переподключения
     */
    public void recordReconnectAttempt(boolean success) {
        clientMetrics.recordReconnectAttempt(success);
    }
    
    // ========== SHUTDOWN ==========
    
    @PreDestroy
    public void shutdown() throws InterruptedException {
        clientMetrics.stop();
        
        if (goChannel != null) {
            goChannel.shutdown().awaitTermination(5, TimeUnit.SECONDS);
        }
        if (elixirChannel != null) {
            elixirChannel.shutdown().awaitTermination(5, TimeUnit.SECONDS);
        }
        if (pythonChannel != null) {
            pythonChannel.shutdown().awaitTermination(5, TimeUnit.SECONDS);
        }
        logger.info("🔌 Все gRPC клиенты отключены, метрики сохранены");
    }
}