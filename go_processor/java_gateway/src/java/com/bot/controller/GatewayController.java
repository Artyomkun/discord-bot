package com.bot.controller;

import com.bot.services.KafkaProducerService;
import com.bot.services.PythonService;
import com.bot.services.RouterService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api")
public class GatewayController {

    @Autowired
    private KafkaProducerService kafkaProducer;

    @Autowired
    private PythonService pythonService;

    @Autowired
    private RouterService routerService;

    /**
     * Основной эндпоинт для обработки аудио
     * Отправляет команду в Kafka вместо прямого вызова GoBridge
     */
    @PostMapping("/process")
    public Mono<Map<String, Object>> processAudio(@RequestBody AudioRequest request) {
        System.out.println("📥 Получен запрос на обработку аудио: " + request.getUrl());

        String requestId = UUID.randomUUID().toString();
        
        // Формируем событие для Kafka
        Map<String, Object> event = new HashMap<>();
        event.put("request_id", requestId);
        event.put("command", "play");
        event.put("url", request.getUrl());
        event.put("format", request.getFormat());
        event.put("volume", request.getVolume());
        event.put("user_id", request.getUserId());
        event.put("guild_id", request.getGuildId());
        event.put("voice_channel_id", request.getVoiceChannelId());
        event.put("timestamp", System.currentTimeMillis());

        // Отправляем в Kafka
        kafkaProducer.sendCommand("play", event);

        // Возвращаем сразу ответ, что команда принята в очередь
        return Mono.just(Map.of(
            "status", "queued",
            "request_id", requestId,
            "message", "Audio processing request queued in Kafka",
            "timestamp", System.currentTimeMillis()
        ));
    }

    /**
     * Health check всего Gateway
     */
    @GetMapping("/health")
    public Mono<Map<String, Object>> health() {
        return Mono.just(Map.of(
            "service", "java-gateway",
            "status", "running",
            "kafka_available", kafkaProducer.isKafkaAvailable(),
            "python_service_available", pythonService.isPythonAvailable(),
            "timestamp", System.currentTimeMillis()
        ));
    }

    /**
     * Статистика (информация о состоянии)
     */
    @GetMapping("/stats")
    public Mono<Map<String, Object>> stats() {
        Map<String, Object> stats = new HashMap<>();
        stats.put("gateway_status", "active");
        stats.put("kafka_available", kafkaProducer.isKafkaAvailable());
        stats.put("python_available", pythonService.isPythonAvailable());
        stats.put("uptime", System.currentTimeMillis());
        return Mono.just(stats);
    }

    /**
     * Эндпоинт для команд от Python бота
     */
    @PostMapping("/command")
    public Mono<Map<String, Object>> handlePythonCommand(@RequestBody PythonCommandRequest request) {
        System.out.println("📨 Получена команда от Python бота: " + request.getCommand() +
                          " от пользователя " + request.getUserId());

        // Тоже отправляем в Kafka
        Map<String, Object> event = new HashMap<>();
        event.put("request_id", UUID.randomUUID().toString());
        event.put("command", request.getCommand());
        event.put("url", request.getUrl());
        event.put("user_id", request.getUserId());
        event.put("guild_id", request.getGuildId());
        event.put("channel_id", request.getChannelId());
        event.put("options", request.getOptions());
        event.put("source", "python_bot");
        event.put("timestamp", System.currentTimeMillis());

        kafkaProducer.sendCommand(request.getCommand(), event);

        return Mono.just(Map.of(
            "status", "queued",
            "message", "Command forwarded to Kafka",
            "timestamp", System.currentTimeMillis()
        ));
    }

    /**
     * Эндпоинт для регистрации Python бота
     */
    @PostMapping("/register/python")
    public Mono<Map<String, Object>> registerPythonBot(@RequestBody PythonRegistrationRequest request) {
        System.out.println("🤖 Регистрация Python бота: " + request.getBotId());

        return Mono.just(Map.of(
            "status", "registered",
            "bot_id", request.getBotId(),
            "capabilities", List.of("music", "queue", "effects"),
            "timestamp", System.currentTimeMillis()
        ));
    }

    /**
     * Эндпоинт для статуса Python бота
     */
    @GetMapping("/python/status")
    public Mono<Map<String, Object>> getPythonStatus() {
        return Mono.just(Map.of(
            "python_available", pythonService.isPythonAvailable(),
            "last_check", System.currentTimeMillis(),
            "version", "1.0.0"
        ));
    }

    // === DTO (без изменений) ===
    public static class PythonCommandRequest {
        private String command;
        private String url;
        private String userId;
        private String guildId;
        private String channelId;
        private Map<String, Object> options;

        public String getCommand() { return command; }
        public void setCommand(String command) { this.command = command; }
        public String getUrl() { return url; }
        public void setUrl(String url) { this.url = url; }
        public String getUserId() { return userId; }
        public void setUserId(String userId) { this.userId = userId; }
        public String getGuildId() { return guildId; }
        public void setGuildId(String guildId) { this.guildId = guildId; }
        public String getChannelId() { return channelId; }
        public void setChannelId(String channelId) { this.channelId = channelId; }
        public Map<String, Object> getOptions() { return options; }
        public void setOptions(Map<String, Object> options) { this.options = options; }
    }

    public static class PythonRegistrationRequest {
        private String botId;
        private List<String> capabilities;
        private String version;

        public String getBotId() { return botId; }
        public void setBotId(String botId) { this.botId = botId; }
        public List<String> getCapabilities() { return capabilities; }
        public void setCapabilities(List<String> capabilities) { this.capabilities = capabilities; }
        public String getVersion() { return version; }
        public void setVersion(String version) { this.version = version; }
    }

    public static class AudioRequest {
        private String url;
        private String format = "opus";
        private double volume = 1.0;
        private String userId;
        private String guildId;
        private String voiceChannelId;

        public String getUrl() { return url; }
        public void setUrl(String url) { this.url = url; }
        public String getFormat() { return format; }
        public void setFormat(String format) { this.format = format; }
        public double getVolume() { return volume; }
        public void setVolume(double volume) { this.volume = volume; }
        public String getUserId() { return userId; }
        public void setUserId(String userId) { this.userId = userId; }
        public String getGuildId() { return guildId; }
        public void setGuildId(String guildId) { this.guildId = guildId; }
        public String getVoiceChannelId() { return voiceChannelId; }
        public void setVoiceChannelId(String voiceChannelId) { this.voiceChannelId = voiceChannelId; }
    }
}