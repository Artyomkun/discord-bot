package com.bot.controller;

import com.bot.services.KafkaProducerService;
import com.bot.services.PythonService;
import com.bot.services.RegionDetectorService;
import com.bot.services.UserSettingsService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/discord")
public class DiscordWebhookController {

    @Autowired
    private KafkaProducerService kafkaProducer;

    @Autowired
    private PythonService pythonService;

    @Autowired
    private RegionDetectorService regionDetector;

    @Autowired
    private UserSettingsService userSettingsService;

    // Основной вебхук для команд от Discord бота
    @PostMapping("/webhook")
    public Mono<ResponseEntity<Map<String, Object>>> handleDiscordCommand(
            @RequestBody DiscordCommand command) {

        System.out.println("🎮 Команда от Discord: " + command.getCommand() +
                          " от пользователя " + command.getUserId());

        // Определяем тип команды
        return switch (command.getCommand().toLowerCase()) {
            case "play", "audio" -> handleAudioCommand(command);
            case "status", "health" -> handleStatusCommand();
            case "effects" -> handleEffectsCommand(command);
            default -> {
                Map<String, Object> errorResponse = new HashMap<>();
                errorResponse.put("error", "Неизвестная команда: " + command.getCommand());
                yield Mono.just(ResponseEntity.badRequest().body(errorResponse));
            }
        };
    }

    // Обработка аудио-команд (play) — отправляем в Kafka
    private Mono<ResponseEntity<Map<String, Object>>> handleAudioCommand(DiscordCommand command) {
        String url = command.getParameters().get("url");

        if (url == null || url.isEmpty()) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("error", "URL аудио не указан");
            return Mono.just(ResponseEntity.badRequest().body(errorResponse));
        }

        String requestId = UUID.randomUUID().toString();

        // Формируем событие для Kafka
        Map<String, Object> event = new HashMap<>();
        event.put("request_id", requestId);
        event.put("command", "play");
        event.put("url", url);
        event.put("format", command.getParameters().getOrDefault("format", "opus"));
        event.put("volume", command.getParameters().getOrDefault("volume", "1.0"));
        event.put("user_id", command.getUserId());
        event.put("guild_id", command.getGuildId());
        event.put("voice_channel_id", command.getVoiceChannelId());
        event.put("timestamp", System.currentTimeMillis());

        // Отправляем в Kafka
        kafkaProducer.sendCommand("play", event);

        // Возвращаем ответ сразу (команда в очереди)
        Map<String, Object> response = new HashMap<>();
        response.put("status", "queued");
        response.put("request_id", requestId);
        response.put("message", "Аудио отправлено на обработку через Kafka");
        response.put("command_id", command.getCommandId());

        return Mono.just(ResponseEntity.ok(response));
    }

    // Проверка статуса сервисов
    private Mono<ResponseEntity<Map<String, Object>>> handleStatusCommand() {
        Map<String, Object> response = new HashMap<>();
        response.put("service", "java-gateway");
        response.put("status", "running");
        response.put("kafka_available", kafkaProducer.isKafkaAvailable());
        response.put("python_bot", pythonService.isPythonAvailable() ? "connected" : "disconnected");
        response.put("timestamp", System.currentTimeMillis());

        return Mono.just(ResponseEntity.ok(response));
    }

    // Команды управления эффектами (отправляем в Kafka)
    private Mono<ResponseEntity<Map<String, Object>>> handleEffectsCommand(DiscordCommand command) {
        String action = command.getParameters().get("action");

        String requestId = UUID.randomUUID().toString();

        Map<String, Object> event = new HashMap<>();
        event.put("request_id", requestId);
        event.put("command", "effects");
        event.put("action", action);
        event.put("user_id", command.getUserId());
        event.put("guild_id", command.getGuildId());
        event.put("voice_channel_id", command.getVoiceChannelId());
        event.put("timestamp", System.currentTimeMillis());

        kafkaProducer.sendCommand("effects", event);

        Map<String, Object> response = new HashMap<>();
        response.put("status", "queued");
        response.put("request_id", requestId);
        response.put("message", "Команда эффектов отправлена в очередь");
        response.put("command_id", command.getCommandId());

        return Mono.just(ResponseEntity.ok(response));
    }

    // Поиск музыки
    @GetMapping("/search")
    public Mono<Map<String, Object>> searchMusic(
            @RequestParam String query,
            @RequestParam String userId,
            @RequestParam(defaultValue = "AUTO") String region,
            @RequestParam(defaultValue = "10") int limit,
            @RequestParam(required = false) String guildId,
            @RequestParam(required = false) String voiceChannelId) {

        // Определяем регион
        MusicRegion effectiveRegion = MusicRegion.valueOf(region.toUpperCase());
        if (effectiveRegion == MusicRegion.AUTO) {
            effectiveRegion = regionDetector.detectRegion(userId);
            log.info("Auto-detected region for user {}: {}", userId, effectiveRegion);
        }

        String source = effectiveRegion == MusicRegion.RUSSIAN ? "russian_fallback" : "youtube";

        // Отправляем поисковый запрос в Kafka
        String requestId = UUID.randomUUID().toString();

        Map<String, Object> event = new HashMap<>();
        event.put("request_id", requestId);
        event.put("command", "search");
        event.put("query", query);
        event.put("source", source);
        event.put("limit", limit);
        event.put("user_id", userId);
        event.put("guild_id", guildId);
        event.put("voice_channel_id", voiceChannelId);
        event.put("timestamp", System.currentTimeMillis());

        kafkaProducer.sendCommand("search", event);

        return Mono.just(Map.of(
            "status", "queued",
            "request_id", requestId,
            "message", "Поисковый запрос отправлен в очередь"
        ));
    }

    // Быстрый health check для мониторинга
    @GetMapping("/ping")
    public ResponseEntity<Map<String, Object>> ping() {
        return ResponseEntity.ok(Map.of(
            "status", "pong",
            "service", "discord-webhook",
            "timestamp", System.currentTimeMillis()
        ));
    }

    // DTO для команд от Discord
    public static class DiscordCommand {
        private String command;
        private String userId;
        private String guildId;
        private String channelId;
        private String voiceChannelId;
        private String commandId;
        private Map<String, String> parameters;

        public String getCommand() { return command; }
        public void setCommand(String command) { this.command = command; }
        public String getUserId() { return userId; }
        public void setUserId(String userId) { this.userId = userId; }
        public String getGuildId() { return guildId; }
        public void setGuildId(String guildId) { this.guildId = guildId; }
        public String getChannelId() { return channelId; }
        public void setChannelId(String channelId) { this.channelId = channelId; }
        public String getCommandId() { return commandId; }
        public void setCommandId(String commandId) { this.commandId = commandId; }
        public Map<String, String> getParameters() {
            return parameters != null ? parameters : new HashMap<>();
        }
        public void setParameters(Map<String, String> parameters) { this.parameters = parameters; }
        public String getVoiceChannelId() { return voiceChannelId; }
        public void setVoiceChannelId(String voiceChannelId) { this.voiceChannelId = voiceChannelId; }
    }

    public enum MusicRegion {
        RUSSIAN, FOREIGN, AUTO
    }
}