package com.bot.services;

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
public class GoClientService {

    private final WebClient webClient;
    private final MeterRegistry meterRegistry;

    @Value("${go.processor.timeout:30}")
    private int timeoutSeconds;

    @Value("${go.processor.url:http://localhost:8081}")
    private String goProcessorUrl;

    public GoClientService(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;

        String baseUrl = System.getenv("GO_PROCESSOR_URL");
        if (baseUrl == null || baseUrl.isEmpty()) {
            baseUrl = goProcessorUrl;
        }

        this.webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .defaultHeader("Accept", "application/json")
                .defaultHeader("User-Agent", "Java-Gateway/1.0")
                .build();
    }

    /**
     * Общий метод для POST-запросов с ретраями и метриками
     */
    private Mono<Map<String, Object>> postRequest(String uri, Map<String, Object> body, Duration timeout, String methodName) {
        meterRegistry.counter("go.client.requests", "method", methodName, "uri", uri).increment();
        long startTime = System.currentTimeMillis();

        return webClient.post()
                .uri(uri)
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(body)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(timeout)
                .retryWhen(Retry.backoff(3, Duration.ofSeconds(1))
                        .maxBackoff(Duration.ofSeconds(10))
                        .filter(throwable -> throwable instanceof WebClientResponseException.ServiceUnavailable))
                .doOnSuccess(response -> {
                    long duration = System.currentTimeMillis() - startTime;
                    meterRegistry.timer("go.client.latency", "method", methodName, "uri", uri)
                            .record(Duration.ofMillis(duration));
                })
                .onErrorResume(WebClientResponseException.class, ex -> {
                    meterRegistry.counter("go.client.errors", "method", methodName, "error", "http_" + ex.getStatusCode()).increment();
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Service error: " + ex.getStatusCode());
                    errorResponse.put("message", ex.getResponseBodyAsString());
                    errorResponse.put("status", "failed");
                    return Mono.just(errorResponse);
                })
                .onErrorResume(Exception.class, ex -> {
                    meterRegistry.counter("go.client.errors", "method", methodName, "error", "connection").increment();
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Connection failed");
                    errorResponse.put("message", ex.getMessage());
                    errorResponse.put("status", "connection_error");
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Отправляет аудио на обработку в Go-сервис
     */
    @Retry(name = "goClient", fallbackMethod = "fallbackProcessAudio")
    public Mono<Map<String, Object>> processAudio(
            String url,
            String format,
            double volume,
            String userId,
            String guildId,
            String voiceChannelId) {

        Map<String, Object> body = Map.of(
                "url", url,
                "format", format != null ? format : "opus",
                "volume", volume,
                "user_id", userId,
                "guild_id", guildId,
                "voice_channel_id", voiceChannelId
        );

        return postRequest("/api/audio/process", body, Duration.ofSeconds(timeoutSeconds), "processAudio");
    }

    /**
     * Fallback при недоступности Go сервиса
     */
    public Mono<Map<String, Object>> fallbackProcessAudio(Exception ex) {
        meterRegistry.counter("go.client.fallback", "method", "processAudio").increment();
        return Mono.just(Map.of(
                "status", "fallback",
                "error", ex.getMessage(),
                "fallback_to", "elixir"
        ));
    }

    /**
     * Применение эффектов к аудио (8D, реверб, эквалайзер)
     */
    @Retry(name = "goClient", fallbackMethod = "fallbackApplyEffects")
    public Mono<Map<String, Object>> applyEffects(
            String audioData,
            String effectType,
            double intensity,
            String userId,
            String guildId,
            String voiceChannelId) {

        Map<String, Object> body = Map.of(
                "audio_data", audioData,
                "effect_type", effectType,
                "intensity", intensity,
                "user_id", userId,
                "guild_id", guildId,
                "voice_channel_id", voiceChannelId
        );

        return postRequest("/api/audio/effects", body, Duration.ofSeconds(timeoutSeconds), "applyEffects");
    }

    /**
     * Fallback для эффектов
     */
    public Mono<Map<String, Object>> fallbackApplyEffects(Exception ex) {
        meterRegistry.counter("go.client.fallback", "method", "applyEffects").increment();
        return Mono.just(Map.of(
                "status", "fallback",
                "error", ex.getMessage(),
                "message", "Effects applied on fallback mode"
        ));
    }

    /**
     * Получение текущего трека и состояния для голосового канала
     */
    public Mono<Map<String, Object>> getCurrentTrack(String guildId, String voiceChannelId) {
        Map<String, Object> body = Map.of(
                "guild_id", guildId,
                "voice_channel_id", voiceChannelId
        );

        return postRequest("/api/audio/status", body, Duration.ofSeconds(10), "getCurrentTrack");
    }

    /**
     * Проверяет доступность Go-сервиса
     */
    public Mono<Boolean> checkHealth() {
        meterRegistry.counter("go.client.health_check").increment();

        return webClient.get()
                .uri("/health")
                .retrieve()
                .bodyToMono(String.class)
                .map(response -> response.contains("healthy"))
                .timeout(Duration.ofSeconds(5))
                .onErrorReturn(false)
                .doOnSuccess(healthy -> {
                    if (healthy) {
                        meterRegistry.counter("go.client.health_check.success").increment();
                    } else {
                        meterRegistry.counter("go.client.health_check.failure").increment();
                    }
                });
    }

    /**
     * Получает статистику Go-сервиса
     */
    public Mono<Map<String, Object>> getStats() {
        return webClient.get()
                .uri("/stats")
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(10))
                .onErrorResume(ex -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("error", "Failed to get stats");
                    errorResponse.put("message", ex.getMessage());
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
                    meterRegistry.timer("go.client.ping").record(Duration.ofMillis(pingTime));
                    return Mono.just(pingTime);
                })
                .timeout(Duration.ofSeconds(3))
                .onErrorReturn(-1L);
    }

    /**
     * Получить URL текущего трека (удобный метод)
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
                .map(response -> response.containsKey("current_track_url") &&
                        !((String) response.get("current_track_url")).isEmpty())
                .defaultIfEmpty(false);
    }
}