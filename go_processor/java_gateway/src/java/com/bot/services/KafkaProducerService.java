package com.bot.services;

import org.apache.camel.ProducerTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import java.util.Map;

@Service
public class KafkaProducerService {

    @Autowired
    private ProducerTemplate producerTemplate;

    private boolean kafkaAvailable = true;

    public void sendCommand(String commandType, Map<String, Object> payload) {
        if (!kafkaAvailable) {
            System.err.println("⚠️ Kafka недоступна, команда не отправлена: " + commandType);
            return;
        }

        try {
            producerTemplate.sendBody("direct:send-to-kafka", Map.of(
                "command", commandType,
                "payload", payload,
                "timestamp", System.currentTimeMillis()
            ));
        } catch (Exception e) {
            System.err.println("❌ Ошибка отправки в Kafka: " + e.getMessage());
            kafkaAvailable = false;
        }
    }

    public boolean isKafkaAvailable() {
        return kafkaAvailable;
    }
}