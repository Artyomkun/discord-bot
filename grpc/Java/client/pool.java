package com.bot.grpc.client;

import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;
import io.grpc.StatusRuntimeException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.logging.Logger;

/**
 * Клиентский пул соединений для отправки gRPC запросов на сервер
 * Используется в: Go сервис, Python скрипты, Elixir сервис
 */
public class pool {
    private static final Logger logger = Logger.getLogger(pool.class.getName());
    
    private static volatile pool instance;
    private static final Object lock = new Object();
    
    private ManagedChannel channel;
    private AudioServiceGrpc.AudioServiceBlockingStub stub;
    
    private String host;
    private int port;
    private boolean connected;
    private int connectionId;
    private static final AtomicInteger connectionCounter = new AtomicInteger(0);
    
    // Конфигурация
    private static final long TIMEOUT_MS = 30000;
    private static final long KEEP_ALIVE_MS = 30000;
    
    private pool(String host, int port) {
        this.host = host;
        this.port = port;
        this.connectionId = connectionCounter.incrementAndGet();
        connect();
    }
    
    public static pool getInstance() {
        return getInstance("localhost", 50051);
    }
    
    public static pool getInstance(String host, int port) {
        if (instance == null) {
            synchronized (lock) {
                if (instance == null) {
                    instance = new pool(host, port);
                }
            }
        }
        return instance;
    }
    
    private void connect() {
        try {
            if (channel != null && !channel.isShutdown()) {
                channel.shutdown();
                try {
                    channel.awaitTermination(1, TimeUnit.SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            
            channel = ManagedChannelBuilder.forAddress(host, port)
                    .usePlaintext()
                    .keepAliveTime(KEEP_ALIVE_MS, TimeUnit.MILLISECONDS)
                    .keepAliveTimeout(5000, TimeUnit.MILLISECONDS)
                    .keepAliveWithoutCalls(true)
                    .maxInboundMessageSize(100 * 1024 * 1024) // 100MB для аудио
                    .build();
            
            stub = AudioServiceGrpc.newBlockingStub(channel);
            connected = true;
            
            logger.info(String.format("✅ Клиент #%d подключен к серверу %s:%d", 
                connectionId, host, port));
            
        } catch (Exception e) {
            logger.severe(String.format("❌ Клиент #%d ошибка подключения: %s", 
                connectionId, e.getMessage()));
            connected = false;
        }
    }
    
    public void reconnect() {
        logger.info(String.format("🔄 Клиент #%d переподключение...", connectionId));
        connect();
    }
    
    public boolean isConnected() {
        return connected && channel != null && !channel.isShutdown();
    }
    
    public AudioServiceGrpc.AudioServiceBlockingStub getStub() {
        if (!isConnected()) {
            reconnect();
            if (!isConnected()) {
                throw new RuntimeException("No connection to server");
            }
        }
        return stub;
    }
    
    // ========== МЕТОДЫ ДЛЯ ВЫЗОВА СЕРВЕРА ==========
    
    public AudioServiceProto.PlayResponse play(String guildId, String userId, String url, 
                                                 String voiceChannelId) {
        AudioServiceProto.PlayRequest request = AudioServiceProto.PlayRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .setUrl(url)
                .setVoiceChannelId(voiceChannelId)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .play(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in play: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    public AudioServiceProto.StopResponse stop(String guildId) {
        AudioServiceProto.StopRequest request = AudioServiceProto.StopRequest.newBuilder()
                .setGuildId(guildId)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .stop(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in stop: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    public AudioServiceProto.PauseResponse pause(String guildId) {
        AudioServiceProto.PauseRequest request = AudioServiceProto.PauseRequest.newBuilder()
                .setGuildId(guildId)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .pause(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in pause: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    public AudioServiceProto.ResumeResponse resume(String guildId) {
        AudioServiceProto.ResumeRequest request = AudioServiceProto.ResumeRequest.newBuilder()
                .setGuildId(guildId)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .resume(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in resume: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    public AudioServiceProto.SkipResponse skip(String guildId) {
        AudioServiceProto.SkipRequest request = AudioServiceProto.SkipRequest.newBuilder()
                .setGuildId(guildId)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .skip(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in skip: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    public AudioServiceProto.VolumeResponse setVolume(String guildId, int volume) {
        AudioServiceProto.VolumeRequest request = AudioServiceProto.VolumeRequest.newBuilder()
                .setGuildId(guildId)
                .setVolume(volume)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .volume(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in setVolume: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    public AudioServiceProto.QueueResponse getQueue(String guildId) {
        AudioServiceProto.QueueRequest request = AudioServiceProto.QueueRequest.newBuilder()
                .setGuildId(guildId)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .getQueue(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in getQueue: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    public AudioServiceProto.StatusResponse getStatus(String guildId) {
        AudioServiceProto.StatusRequest request = AudioServiceProto.StatusRequest.newBuilder()
                .setGuildId(guildId)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .getStatus(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in getStatus: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    // ========== МЕТОДЫ ДЛЯ ELIXIR (MUSIC + 5D) ==========
    
    /**
     * Получить статус воспроизведения из Elixir сервиса
     */
    public AudioServiceProto.StatusResponse getStatusFromElixir(String guildId) {
        AudioServiceProto.StatusRequest request = AudioServiceProto.StatusRequest.newBuilder()
                .setGuildId(guildId)
                .build();
        
        try {
            AudioServiceProto.StatusResponse response = getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .getStatus(request);
            
            if (response.getSuccess()) {
                logger.info(String.format("🎵 Elixir status: playing=%s, track=%s, volume=%d",
                    response.getPlaying(),
                    response.hasCurrentTrack() ? response.getCurrentTrack().getTitle() : "none",
                    response.getVolume()));
            }
            
            return response;
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in getStatusFromElixir: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    /**
     * Получить очередь из Elixir сервиса
     */
    public AudioServiceProto.QueueResponse getQueueFromElixir(String guildId) {
        AudioServiceProto.QueueRequest request = AudioServiceProto.QueueRequest.newBuilder()
                .setGuildId(guildId)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .getQueue(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in getQueueFromElixir: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    /**
     * Применить 5D-эффект через Elixir сервис
     */
    public AudioServiceProto.EffectsResponse applyEffectsInElixir(String guildId, String userId, 
                                                                   String effectType, double intensity,
                                                                   java.util.Map<String, String> params) {
        AudioServiceProto.EffectsRequest.Builder builder = AudioServiceProto.EffectsRequest.newBuilder()
                .setGuildId(guildId)
                .setUserId(userId)
                .setEffectType(effectType)
                .setIntensity(intensity);
        
        if (params != null) {
            builder.putAllParams(params);
        }
        
        AudioServiceProto.EffectsRequest request = builder.build();
        
        try {
            AudioServiceProto.EffectsResponse response = getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .applyEffects(request);
            
            if (response.getSuccess()) {
                logger.info(String.format("✨ 5D effect applied via Elixir: %s (intensity=%.2f)", 
                    effectType, intensity));
            }
            
            return response;
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in applyEffectsInElixir: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    /**
     * Пропустить трек в Elixir сервисе
     */
    public AudioServiceProto.SkipResponse skipInElixir(String guildId) {
        AudioServiceProto.SkipRequest request = AudioServiceProto.SkipRequest.newBuilder()
                .setGuildId(guildId)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .skip(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in skipInElixir: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    /**
     * Установить громкость в Elixir сервисе
     */
    public AudioServiceProto.VolumeResponse setVolumeInElixir(String guildId, int volume) {
        AudioServiceProto.VolumeRequest request = AudioServiceProto.VolumeRequest.newBuilder()
                .setGuildId(guildId)
                .setVolume(volume)
                .build();
        
        try {
            return getStub().withDeadlineAfter(TIMEOUT_MS, TimeUnit.MILLISECONDS)
                    .volume(request);
        } catch (StatusRuntimeException e) {
            logger.severe("gRPC error in setVolumeInElixir: " + e.getStatus());
            reconnect();
            throw e;
        }
    }
    
    /**
     * Health check для Elixir сервиса
     */
    public AudioServiceProto.HealthResponse healthCheckElixir() {
        AudioServiceProto.HealthRequest request = AudioServiceProto.HealthRequest.newBuilder()
                .build();
        
        try {
            return getStub().withDeadlineAfter(5000, TimeUnit.MILLISECONDS)
                    .healthCheck(request);
        } catch (StatusRuntimeException e) {
            logger.warning("Elixir health check failed: " + e.getStatus());
            return AudioServiceProto.HealthResponse.newBuilder()
                    .setStatus("unhealthy")
                    .setMessage("Elixir connection failed: " + e.getStatus().getCode())
                    .build();
        }
    }
    
    /**
     * Получить полный статус системы (агрегированный из всех сервисов)
     */
    public SystemStatus getSystemStatus() {
        SystemStatus status = new SystemStatus();
        
        // Статус Go
        try {
            status.goHealthy = isConnected();
            if (status.goHealthy) {
                status.goStatus = healthCheck();
            } else {
                status.goStatus = AudioServiceProto.HealthResponse.newBuilder()
                        .setStatus("disconnected")
                        .setMessage("Go service not connected")
                        .build();
            }
        } catch (Exception e) {
            status.goHealthy = false;
            status.goErrorMessage = e.getMessage();
        }
        
        // Статус Elixir
        try {
            AudioServiceProto.HealthResponse elixirHealth = healthCheckElixir();
            status.elixirHealthy = "healthy".equals(elixirHealth.getStatus());
            status.elixirStatus = elixirHealth;
        } catch (Exception e) {
            status.elixirHealthy = false;
            status.elixirErrorMessage = e.getMessage();
        }
        
        return status;
    }
    
    public void shutdown() {
        logger.info(String.format("🛑 Клиент #%d отключается...", connectionId));
        if (channel != null) {
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
        connected = false;
        logger.info(String.format("✅ Клиент #%d отключен", connectionId));
    }
    
    public String getStats() {
        return String.format("Client #%d: %s:%d - connected: %s", 
            connectionId, host, port, isConnected());
    }
    
    /**
     * Внутренний класс для агрегированного статуса системы
     */
    public static class SystemStatus {
        public boolean goHealthy;
        public boolean elixirHealthy;
        public AudioServiceProto.HealthResponse goStatus;
        public AudioServiceProto.HealthResponse elixirStatus;
        public String goErrorMessage;
        public String elixirErrorMessage;
        
        public boolean isAllHealthy() {
            return goHealthy && elixirHealthy;
        }
        
        public String getSummary() {
            return String.format("System Status: Go=%s, Elixir=%s",
                goHealthy ? "✅" : "❌",
                elixirHealthy ? "✅" : "❌");
        }
    }
}