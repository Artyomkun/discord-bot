package com.bot.services;

import com.bot.config.RetryConfig;
import io.github.resilience4j.retry.annotation.Retry;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

@Service
public class GoBridge {

    private final WebClient webClient;
    private final MeterRegistry meterRegistry;

    @Value("${go.processor.timeout:30}")
    private int timeoutSeconds;

    @Value("${go.processor.url:http://localhost:8081}")
    private String goProcessorUrl;

    public GoBridge(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;

        String url = System.getenv("GO_PROCESSOR_URL") != null ?
                System.getenv("GO_PROCESSOR_URL") : goProcessorUrl;

        this.webClient = WebClient.builder()
                .baseUrl(url)
                .defaultHeader("Content-Type", "application/json")
                .defaultHeader("User-Agent", "Java-Gateway/1.0")
                .build();
    }

    /**
     * Вызов Go-сервиса для обработки аудио (play)
     */
    @Retry(name = "goBridge", fallbackMethod = "fallbackProcessAudio")
    public Mono<Map<String, Object>> processAudio(
            String url,
            String format,
            double volume,
            String userId,
            String guildId,
            String voiceChannelId) {

        meterRegistry.counter("go.bridge.requests", "method", "process_audio").increment();
        long startTime = System.currentTimeMillis();

        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("url", url);
        requestBody.put("format", format != null ? format : "opus");
        requestBody.put("volume", volume);
        requestBody.put("user_id", userId);
        requestBody.put("guild_id", guildId);
        requestBody.put("voice_channel_id", voiceChannelId);

        return webClient.post()
                .uri("/api/audio/process")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(requestBody)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(timeoutSeconds))
                .retryWhen(Retry.backoff(3, Duration.ofSeconds(1))
                        .maxBackoff(Duration.ofSeconds(10))
                        .filter(throwable -> throwable instanceof WebClientResponseException.ServiceUnavailable))
                .doOnSuccess(response -> {
                    long duration = System.currentTimeMillis() - startTime;
                    meterRegistry.timer("go.bridge.latency", "method", "process_audio")
                            .record(Duration.ofMillis(duration));
                })
                .onErrorResume(WebClientResponseException.class, ex -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Go service error: " + ex.getStatusCode());
                    errorResponse.put("message", ex.getResponseBodyAsString());
                    errorResponse.put("status", "failed");
                    return Mono.just(errorResponse);
                })
                .onErrorResume(Exception.class, ex -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Connection failed");
                    errorResponse.put("message", ex.getMessage());
                    errorResponse.put("status", "connection_error");
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Fallback метод при недоступности Go сервиса
     */
    public Mono<Map<String, Object>> fallbackProcessAudio(Exception ex) {
        meterRegistry.counter("go.bridge.fallback", "method", "process_audio").increment();
        return Mono.just(Map.of(
                "status", "fallback",
                "error", ex.getMessage(),
                "fallback_to", "elixir"
        ));
    }

    /**
     * Применение эффектов к аудио (8D, реверб, эквалайзер)
     */
    @Retry(name = "goBridge", fallbackMethod = "fallbackApplyEffects")
    public Mono<Map<String, Object>> applyEffects(
            String audioData,
            String effectType,
            double intensity,
            String userId,
            String guildId,
            String voiceChannelId) {

        meterRegistry.counter("go.bridge.requests", "method", "apply_effects").increment();
        long startTime = System.currentTimeMillis();

        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("audio_data", audioData);
        requestBody.put("effect_type", effectType);
        requestBody.put("intensity", intensity);
        requestBody.put("user_id", userId);
        requestBody.put("guild_id", guildId);
        requestBody.put("voice_channel_id", voiceChannelId);

        return webClient.post()
                .uri("/api/audio/effects")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(requestBody)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(timeoutSeconds))
                .doOnSuccess(response -> {
                    long duration = System.currentTimeMillis() - startTime;
                    meterRegistry.timer("go.bridge.latency", "method", "apply_effects")
                            .record(Duration.ofMillis(duration));
                })
                .onErrorResume(ex -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Failed to apply effect");
                    errorResponse.put("message", ex.getMessage());
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Fallback для эффектов
     */
    public Mono<Map<String, Object>> fallbackApplyEffects(Exception ex) {
        meterRegistry.counter("go.bridge.fallback", "method", "apply_effects").increment();
        return Mono.just(Map.of(
                "status", "fallback",
                "error", ex.getMessage(),
                "fallback_to", "elixir"
        ));
    }

    /**
     * Получение текущего трека и состояния для голосового канала
     */
    public Mono<Map<String, Object>> getCurrentTrack(String guildId, String voiceChannelId) {
        meterRegistry.counter("go.bridge.requests", "method", "get_current_track").increment();

        Map<String, Object> params = new HashMap<>();
        params.put("guild_id", guildId);
        params.put("voice_channel_id", voiceChannelId);

        return webClient.post()
                .uri("/api/audio/status")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(params)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(10))
                .onErrorResume(ex -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Failed to get track status");
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Управление воспроизведением (pause/resume/stop/skip)
     */
    public Mono<Map<String, Object>> playbackControl(
            String guildId,
            String voiceChannelId,
            String action,
            Map<String, Object> params) {

        meterRegistry.counter("go.bridge.requests", "method", "playback_control").increment();

        Map<String, Object> requestBody = new HashMap<>();
        requestBody.put("guild_id", guildId);
        requestBody.put("voice_channel_id", voiceChannelId);
        requestBody.put("action", action);
        if (params != null) {
            requestBody.putAll(params);
        }

        return webClient.post()
                .uri("/api/audio/control")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(requestBody)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(10))
                .onErrorResume(ex -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Failed to control playback");
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Health check Go-сервиса
     */
    public Mono<Boolean> healthCheck() {
        return webClient.get()
                .uri("/health")
                .retrieve()
                .bodyToMono(String.class)
                .map(response -> response.contains("healthy"))
                .timeout(Duration.ofSeconds(5))
                .onErrorReturn(false);
    }

    /**
     * Получение статистики Go-сервиса
     */
    public Mono<Map<String, Object>> getGoStats() {
        return webClient.get()
                .uri("/stats")
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(10))
                .onErrorResume(ex -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Failed to get stats");
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Пинг Go-сервиса (быстрая проверка)
     */
    public Mono<Long> ping() {
        long startTime = System.currentTimeMillis();

        return webClient.get()
                .uri("/health")
                .exchangeToMono(response -> {
                    long pingTime = System.currentTimeMillis() - startTime;
                    return Mono.just(pingTime);
                })
                .timeout(Duration.ofSeconds(3))
                .onErrorReturn(-1L);
    }

    /**
     * Получить URL текущего трека
     */
    public Mono<String> getCurrentTrackUrl(String guildId, String voiceChannelId) {
        return getCurrentTrack(guildId, voiceChannelId)
                .map(response -> (String) response.getOrDefault("current_track_url", ""))
                .defaultIfEmpty("");
    }

    /**
     * Проверка, играет ли сейчас что-то в канале
     */
    public Mono<Boolean> isPlaying(String guildId, String voiceChannelId) {
        return getCurrentTrack(guildId, voiceChannelId)
                .map(response -> response.containsKey("current_track_url") && !((String) response.get("current_track_url")).isEmpty())
                .defaultIfEmpty(false);
    }
}