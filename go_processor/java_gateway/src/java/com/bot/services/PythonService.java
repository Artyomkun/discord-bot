package com.bot.services;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

@Service
public class PythonService {

    private final WebClient webClient;
    private final MeterRegistry meterRegistry;

    @Value("${custom.external.services.python-bot.url:http://localhost:5000}")
    private String pythonBotUrl;

    @Value("${custom.external.services.python-bot.timeout:30}")
    private int timeoutSeconds;

    public PythonService(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
        
        String baseUrl = System.getenv("PYTHON_BOT_URL") != null ? 
                         System.getenv("PYTHON_BOT_URL") : "http://localhost:5000";
        
        this.webClient = WebClient.builder()
                .baseUrl(baseUrl)
                .defaultHeader("Content-Type", "application/json")
                .defaultHeader("User-Agent", "Java-Gateway/1.0")
                .build();
    }

    /**
     * Отправка команды в Python бот (реактивно, без блокировок)
     */
    public Mono<Map<String, Object>> sendCommandToPython(String command, String url, String userID, String guildID) {
        meterRegistry.counter("python.service.requests", "method", "sendCommand").increment();
        
        Map<String, Object> requestBody = Map.of(
                "command", command,
                "url", url,
                "user_id", userID,
                "guild_id", guildID
        );

        return webClient.post()
                .uri("/api/command")
                .bodyValue(requestBody)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(timeoutSeconds))
                .doOnSuccess(response -> {
                    meterRegistry.counter("python.service.success", "method", "sendCommand").increment();
                })
                .onErrorResume(e -> {
                    meterRegistry.counter("python.service.errors", "method", "sendCommand").increment();
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("status", "error");
                    errorResponse.put("error", e.getMessage());
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Проверка доступности Python бота (реактивно)
     */
    public Mono<Boolean> checkPythonHealth() {
        return webClient.get()
                .uri("/health")
                .retrieve()
                .bodyToMono(String.class)
                .map(response -> response.contains("healthy") || response.contains("ok"))
                .timeout(Duration.ofSeconds(5))
                .onErrorReturn(false);
    }

    /**
     * Получение статуса Python бота
     */
    public Mono<Map<String, Object>> getPythonStatus() {
        return webClient.get()
                .uri("/status")
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(10))
                .onErrorResume(e -> {
                    Map<String, Object> errorResponse = new HashMap<>();
                    errorResponse.put("status", "error");
                    errorResponse.put("error", e.getMessage());
                    return Mono.just(errorResponse);
                });
    }

    /**
     * Временная заглушка для совместимости
     */
    public Map<String, Object> simulatePythonCommand(String command) {
        Map<String, Object> response = new HashMap<>();
        response.put("status", "simulated");
        response.put("command", command);
        response.put("message", "Python бот ещё не реализован");
        response.put("fallback", true);
        return response;
    }

    /**
     * Реактивная проверка доступности Python
     */
    public Mono<Boolean> isPythonAvailableReactive() {
        return checkPythonHealth();
    }

    /**
     * Блокирующая проверка (только для случаев, где реально нужна)
     * @deprecated Используй isPythonAvailableReactive() в реактивном коде
     */
    @Deprecated
    public boolean isPythonAvailable() {
        try {
            Boolean available = checkPythonHealth().block(Duration.ofSeconds(5));
            return available != null && available;
        } catch (Exception e) {
            return false;
        }
    }
}