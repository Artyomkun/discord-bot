package com.bot.services;

import io.github.resilience4j.retry.annotation.Retry;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

@Service
public class ElixirBridge {

    private final WebClient webClient;
    private final MeterRegistry meterRegistry;

    @Value("${custom.elixir.base-url:http://localhost:4000}")
    private String elixirBaseUrl;

    @Value("${custom.elixir.timeout:60}")
    private int timeoutSeconds;

    public ElixirBridge(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
        
        String baseUrl = System.getenv("ELIXIR_CORE_URL") != null ? 
                         System.getenv("ELIXIR_CORE_URL") : "http://localhost:4000";
        
        this.webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .defaultHeader("Accept", "application/json")
                .defaultHeader("Content-Type", "application/json")
                .defaultHeader("User-Agent", "Java-Gateway/1.0")
                .build();
    }

    /**
     * Обработка аудио через Elixir (музыкальные потоки)
     */
    @Retry(name = "elixirBridge", fallbackMethod = "fallbackProcessAudioStream")
    public Mono<Map<String, Object>> processAudioStream(
            String url,
            String userId,
            String guildId,
            String voiceChannelId) {

        meterRegistry.counter("elixir.bridge.requests", "method", "processAudioStream").increment();
        long startTime = System.currentTimeMillis();

        Map<String, Object> requestBody = Map.of(
                "url", url,
                "user_id", userId,
                "guild_id", guildId,
                "voice_channel_id", voiceChannelId,
                "action", "play"
        );

        return webClient.post()
                .uri("/api/audio/stream")
                .bodyValue(requestBody)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(timeoutSeconds))
                .retryWhen(Retry.backoff(3, Duration.ofSeconds(1))
                        .maxBackoff(Duration.ofSeconds(10)))
                .doOnSuccess(response -> {
                    long duration = System.currentTimeMillis() - startTime;
                    meterRegistry.timer("elixir.bridge.latency", "method", "processAudioStream")
                            .record(Duration.ofMillis(duration));
                })
                .onErrorResume(e -> {
                    meterRegistry.counter("elixir.bridge.errors", "method", "processAudioStream").increment();
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Elixir service unavailable");
                    errorResponse.put("message", e.getMessage());
                    errorResponse.put("fallback", true);
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Fallback для processAudioStream
     */
    public Mono<Map<String, Object>> fallbackProcessAudioStream(Exception ex) {
        meterRegistry.counter("elixir.bridge.fallback", "method", "processAudioStream").increment();
        return Mono.just(Map.of(
                "status", "fallback",
                "error", ex.getMessage(),
                "fallback_to", "python"
        ));
    }

    /**
     * Управление воспроизведением (play/pause/stop/skip/volume)
     */
    public Mono<Map<String, Object>> playbackControl(
            String guildId,
            String voiceChannelId,
            String action,
            Map<String, Object> params) {

        meterRegistry.counter("elixir.bridge.requests", "method", "playbackControl").increment();

        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("guild_id", guildId);
        requestBody.put("voice_channel_id", voiceChannelId);
        requestBody.put("action", action);
        if (params != null) {
            requestBody.putAll(params);
        }

        return webClient.post()
                .uri("/api/audio/control")
                .bodyValue(requestBody)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(30))
                .onErrorResume(e -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Failed to control playback");
                    errorResponse.put("message", e.getMessage());
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Получение текущего состояния для голосового канала
     */
    public Mono<Map<String, Object>> getVoiceChannelState(String guildId, String voiceChannelId) {
        Map<String, Object> params = Map.of(
                "guild_id", guildId,
                "voice_channel_id", voiceChannelId
        );

        return webClient.post()
                .uri("/api/audio/state")
                .bodyValue(params)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(10))
                .onErrorResume(e -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Failed to get state");
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Проверка, кто находится в голосовом канале
     */
    public Mono<Map<String, Object>> getVoiceChannelUsers(String guildId, String voiceChannelId) {
        Map<String, Object> params = Map.of(
                "guild_id", guildId,
                "voice_channel_id", voiceChannelId
        );

        return webClient.post()
                .uri("/api/voice/users")
                .bodyValue(params)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(10))
                .onErrorResume(e -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Failed to get users");
                    errorResponse.put("users", new String[]{});
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Применение эффектов к аудио
     */
    public Mono<Map<String, Object>> applyAudioEffects(
            String audioData,
            Map<String, Object> effects,
            String userId,
            String guildId,
            String voiceChannelId) {

        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("audio_data", audioData);
        requestBody.put("effects", effects);
        requestBody.put("user_id", userId);
        requestBody.put("guild_id", guildId);
        requestBody.put("voice_channel_id", voiceChannelId);
        requestBody.put("preset", effects.getOrDefault("preset", "balanced"));

        return webClient.post()
                .uri("/api/audio/effects")
                .bodyValue(requestBody)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(30));
    }

    /**
     * Получение статуса FFmpeg аудио-обработчика
     */
    public Mono<Map<String, Object>> getFFmpegStatus() {
        return webClient.get()
                .uri("/api/ffmpeg/status")
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(5))
                .onErrorResume(e -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("status", "disconnected");
                    errorResponse.put("processor", "ffmpeg");
                    errorResponse.put("error", "FFmpeg service unavailable");
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Получение пресетов эффектов из Elixir
     */
    public Mono<Map<String, Object>> getEffectsPresets(String userId) {
        return webClient.get()
                .uri("/api/effects/presets?user_id=" + userId)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(10));
    }

    /**
     * Обновление настроек эффектов пользователя
     */
    public Mono<Map<String, Object>> updateUserEffects(
            String userId,
            Map<String, Object> effects) {

        Map<String, Object> requestBody = Map.of(
                "user_id", userId,
                "effects", effects
        );

        return webClient.put()
                .uri("/api/users/" + userId + "/effects")
                .bodyValue(requestBody)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {});
    }

    /**
     * Health check Elixir сервиса
     */
    public Mono<Boolean> healthCheck() {
        meterRegistry.counter("elixir.bridge.health_check").increment();

        return webClient.get()
                .uri("/health")
                .retrieve()
                .bodyToMono(String.class)
                .map(response -> response.contains("healthy") || response.contains("ok"))
                .timeout(Duration.ofSeconds(5))
                .onErrorReturn(false)
                .doOnSuccess(healthy -> {
                    if (healthy) {
                        meterRegistry.counter("elixir.bridge.health_check.success").increment();
                    } else {
                        meterRegistry.counter("elixir.bridge.health_check.failure").increment();
                    }
                });
    }

    /**
     * Получение метрик из Elixir (Prometheus)
     */
    public Mono<Map<String, Object>> getMetrics() {
        return webClient.get()
                .uri("/metrics")
                .accept(MediaType.TEXT_PLAIN)
                .retrieve()
                .bodyToMono(String.class)
                .map(metricsText -> {
                    Map<String, Object> metrics = new HashMap<>();
                    metrics.put("raw_metrics", metricsText);
                    return metrics;
                })
                .timeout(Duration.ofSeconds(5));
    }

    /**
     * Управление очередью воспроизведения
     */
    public Mono<Map<String, Object>> queueManagement(
            String guildId,
            String voiceChannelId,
            String action,
            Map<String, Object> track) {

        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("guild_id", guildId);
        requestBody.put("voice_channel_id", voiceChannelId);
        requestBody.put("action", action);
        if (track != null) {
            requestBody.put("track", track);
        }

        return webClient.post()
                .uri("/api/queue/manage")
                .bodyValue(requestBody)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(10));
    }

    /**
     * Удобный метод: проверить, есть ли активный трек в канале
     */
    public Mono<Boolean> isPlaying(String guildId, String voiceChannelId) {
        return getVoiceChannelState(guildId, voiceChannelId)
                .map(state -> {
                    Object isPlaying = state.get("is_playing");
                    return isPlaying instanceof Boolean && (Boolean) isPlaying;
                })
                .defaultIfEmpty(false);
    }

    /**
     * Удобный метод: получить текущий трек
     */
    public Mono<String> getCurrentTrack(String guildId, String voiceChannelId) {
        return getVoiceChannelState(guildId, voiceChannelId)
                .map(state -> (String) state.getOrDefault("current_track", ""))
                .defaultIfEmpty("");
    }
}