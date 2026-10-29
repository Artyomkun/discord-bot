package com.bot.services;

import org.springframework.web.reactive.function.client.WebClientResponseException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.scheduling.annotation.Async;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import org.apache.camel.ProducerTemplate;
import reactor.core.scheduler.Schedulers;
import reactor.core.publisher.Mono;
import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

@Service
public class RouterService {
    
    @Autowired
    private GoBridge goBridge;
    
    @Autowired
    private ElixirBridge elixirBridge;
    
    @Autowired
    private PythonService pythonService;

    @Autowired
    private ProducerTemplate producerTemplate;

    public void sendCommand(String commandType, Map<String, Object> payload) {
        producerTemplate.sendBody("direct:send-to-kafka", Map.of(
            "command", commandType,
            "payload", payload,
            "timestamp", System.currentTimeMillis()
        ));
    }
    
    /**
     * Основной метод маршрутизации
     * Определяет, куда отправить запрос на основе типа команды
     */
    @Cacheable(value = "routingCache", key = "#commandType + '_' + #userId")
    public Mono<Map<String, Object>> routeCommand(
            String commandType,
            String userId,
            Map<String, Object> parameters) {
        
        System.out.println("🔄 RouterService: Маршрутизация команды '" + commandType + "' от пользователя " + userId);

        return switch (commandType.toLowerCase()) {
            case "audio", "play", "process" ->
                // Аудио команды -> Go Service
                routeToGoService(parameters);

            case "music", "stream", "radio" ->
                // Музыкальные потоки -> Elixir
                routeToElixir(userId, parameters);

            case "status", "health" ->
                // Статус всех сервисов
                checkAllServices();

            case "effects", "filter" ->
                // Эффекты -> Elixir
                routeEffectsToElixir(userId, parameters);

            default ->
                // Неизвестная команда -> в Python (если подключен)
                handleUnknownCommand(commandType);
        };
    }
    
    /**
     * Маршрутизация в Go Service для обработки аудио
     */
    @Async
    private Mono<Map<String, Object>> routeToGoService(Map<String, Object> params) {
        String url = (String) params.get("url");
        String format = (String) params.getOrDefault("format", "opus");
        double volume = Double.parseDouble(params.getOrDefault("volume", "1.0").toString());
        String userId = (String) params.get("user_id");
        String guildId = (String) params.get("guild_id");
        String voiceChannelId = (String) params.getOrDefault("voice_channel_id", "");

        System.out.println("🎵 Router -> Go Service: обработка аудио " + url + " для пользователя " + userId + " в канале " + voiceChannelId);

        return GoBridge.processAudio(url, format, volume, userId, guildId, voiceChannelId)
            .timeout(Duration.ofSeconds(30))
            .onErrorResume(WebClientResponseException.class, ex -> {
                Map<String, Object> error = new HashMap<>();
                error.put("status", "error");
                error.put("error", "Go service error: " + ex.getStatusCode());
                error.put("fallback_to", "elixir");
                return Mono.just(error);
            })
            .onErrorResume(Exception.class, ex -> {
                Map<String, Object> error = new HashMap<>();
                error.put("status", "error");
                error.put("error", ex.getMessage());
                error.put("fallback_to", "elixir");
                return Mono.just(error);
            })
            .subscribeOn(Schedulers.boundedElastic())
            .map(response -> {
                Map<String, Object> stats = new HashMap<>();
                stats.put("routed_by", "RouterService");
                stats.put("target_service", "go_processor");
                stats.put("user_id", userId);
                stats.put("guild_id", guildId);
                stats.put("voice_channel_id", voiceChannelId);
                return stats;
            });
    }
    
    /**
     * Маршрутизация в Elixir для музыкальных потоков
     */
    private Mono<Map<String, Object>> routeToElixir(String userId, Map<String, Object> params) {
        String url = (String) params.get("url");
        String guildId = (String) params.getOrDefault("guild_id", "default");
        String voiceChannelId = (String) params.getOrDefault("voice_channel_id", "");

        System.out.println("🎶 Router -> Elixir: музыкальный поток " + url + " для пользователя " + userId + " в канале " + voiceChannelId);

        return elixirBridge.processAudioStream(url, userId, guildId, voiceChannelId)
            .onErrorResume(e -> {
                System.err.println("Elixir error: " + e.getMessage());
                return Mono.just(Map.of(
                    "status", "error",
                    "error", e.getMessage(),
                    "fallback", "go"
                ));
            })
            .map(response -> {
                response.put("routed_by", "RouterService");
                response.put("target_service", "elixir_phoenix");
                return response;
            });
    }
    
    /**
     * Маршрутизация эффектов в Elixir
     */
    private Mono<Map<String, Object>> routeEffectsToElixir(String userId, Map<String, Object> params) {

        String audioData = (String) params.get("audio_data");
        String guildId = (String) params.getOrDefault("guild_id", "");
        String voiceChannelId = (String) params.getOrDefault("voice_channel_id", "");
        
        @SuppressWarnings("unchecked")
        Map<String, Object> effects = (Map<String, Object>) params.getOrDefault("effects", Map.of());

        System.out.println("🎚️ Router -> Elixir: эффекты для пользователя " + userId + " в канале " + voiceChannelId);

        return elixirBridge.applyAudioEffects(audioData, effects, userId, guildId, voiceChannelId)
            .timeout(Duration.ofSeconds(30))
            .onErrorResume(WebClientResponseException.class, ex -> {
                System.err.println("Elixir HTTP error: " + ex.getStatusCode());
                Map<String, Object> fallback = new HashMap<>();
                fallback.put("status", "error");
                fallback.put("error", "Elixir service error: " + ex.getStatusCode());
                fallback.put("fallback_to", "go");
                return Mono.just(fallback);
            })
            .onErrorResume(Exception.class, ex -> {
                System.err.println("Elixir error: " + ex.getMessage());
                Map<String, Object> fallback = new HashMap<>();
                fallback.put("status", "error");
                fallback.put("error", ex.getMessage());
                fallback.put("fallback_to", "go");
                return Mono.just(fallback);
            })
            .subscribeOn(Schedulers.boundedElastic())
            .map(response -> {
                response.put("routed_by", "RouterService");
                response.put("target_service", "elixir_phoenix");
                response.put("user_id", userId);
                response.put("guild_id", guildId);
                response.put("voice_channel_id", voiceChannelId);
                return response;
            });
    }
    
    /**
     * Проверка статуса всех сервисов
     */
    private Mono<Map<String, Object>> checkAllServices() {
        System.out.println("🔍 Router: проверка статуса всех сервисов");
        
        return goBridge.healthCheck()
            .map(goHealthy -> {
                Map<String, Object> status = new HashMap<>();
                status.put("timestamp", System.currentTimeMillis());
                status.put("services", Map.of(
                    "go_processor", goHealthy ? "healthy" : "unhealthy",
                    "elixir_phoenix", "not_implemented",
                    "python_bot", pythonService.isPythonAvailable() ? "connected" : "disconnected",
                    "java_gateway", "running"
                ));
                status.put("router_version", "1.0");
                
                return status;
            });
    }
    
    /**
     * Обработка неизвестных команд
     */
    private Mono<Map<String, Object>> handleUnknownCommand(String commandType) {
        
        System.out.println("❓ Router: неизвестная команда '" + commandType + "'");
        
        // Если Python бот подключен, пробуем отправить туда
        if (pythonService.isPythonAvailable()) {
            System.out.println("   -> перенаправление в Python бот");
            return Mono.just(pythonService.simulatePythonCommand(commandType));
        }
        
        // Иначе возвращаем ошибку
        Map<String, Object> error = new HashMap<>();
        error.put("error", "Unknown command");
        error.put("command", commandType);
        error.put("suggestions", new String[]{"audio", "music", "status", "effects"});
        
        return Mono.just(error);
    }
    
    /**
     * Определяет оптимальный сервис для обработки на основе типа контента
     */
    public String determineTargetService(String contentType, long fileSize) {
        if (contentType == null) {
            return "go";
        }
        
        if (contentType.startsWith("audio/")) {
            return fileSize > 50 * 1024 * 1024 ? "elixir" : "go";
        }
        
        if (contentType.contains("youtube") || contentType.contains("stream")) {
            return "elixir";
        }
        
        return "go";
    }
    
    /**
     * Получает статистику маршрутизации
     */
    public Map<String, Object> getRoutingStats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("total_routed", 0); 
        stats.put("go_service_count", 0);
        stats.put("elixir_service_count", 0);
        stats.put("last_route_time", System.currentTimeMillis());
        
        return stats;
    }
}