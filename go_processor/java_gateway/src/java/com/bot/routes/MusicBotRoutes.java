package com.bot.camel;

import org.apache.camel.builder.RouteBuilder;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class MusicBotRoutes extends RouteBuilder {

    @Value("${kafka.bootstrap.servers:localhost:9092}")
    private String kafkaBrokers;

    @Override
    public void configure() throws Exception {
        
        // === 1. Из HTTP в Kafka ===
        from("direct:send-to-kafka")
            .routeId("http-to-kafka")
            .log("📥 Получена команда: ${body[command]}")
            .marshal().json()
            .to("kafka:commands?brokers=" + kafkaBrokers);

        // === 2. Из Kafka в обработку ===
        from("kafka:commands?brokers=" + kafkaBrokers + "&groupId=java-gateway")
            .routeId("kafka-to-router")
            .unmarshal().json()
            .choice()
                .when(jsonpath("$.command == 'play'"))
                    .to("direct:audio-processing")
                .when(jsonpath("$.command == 'effects'"))
                    .to("direct:effects-processing")
                .when(jsonpath("$.command == 'search'"))
                    .to("direct:search-processing")
                .otherwise()
                    .log("❌ Неизвестная команда: ${body[command]}");

        // === 3. Аудио обработка (Go) ===
        from("direct:audio-processing")
            .routeId("audio-go-processor")
            .log("🎵 Отправка аудио в Go: ${body[url]}")
            .removeHeaders("CamelHttp*")
            .setHeader("Content-Type", constant("application/json"))
            .setBody(simple("${body[payload]}"))
            .to("http://go-processor:8081/api/audio/process?bridgeEndpoint=true")
            .log("✅ Go ответ: ${body}")
            .to("direct:send-result");

        // === 4. Эффекты (Elixir) ===
        from("direct:effects-processing")
            .routeId("effects-elixir-processor")
            .log("🎚️ Отправка эффектов в Elixir: ${body[action]}")
            .removeHeaders("CamelHttp*")
            .setHeader("Content-Type", constant("application/json"))
            .setBody(simple("${body[payload]}"))
            .to("http://elixir-core:4000/api/effects?bridgeEndpoint=true")
            .log("✅ Elixir ответ: ${body}")
            .to("direct:send-result");

        // === 5. Поиск (Python / Elixir) ===
        from("direct:search-processing")
            .routeId("search-processor")
            .log("🔍 Поиск: ${body[query]} через ${body[source]}")
            .choice()
                .when(jsonpath("$.source == 'russian_fallback'"))
                    .to("http://python-bot:5000/api/search/russian?bridgeEndpoint=true")
                .otherwise()
                    .to("http://elixir-core:4000/api/search/youtube?bridgeEndpoint=true")
            .log("📄 Результаты поиска: ${body}")
            .to("direct:send-result");

        // === 6. Отправка результата обратно в Kafka ===
        from("direct:send-result")
            .routeId("result-to-kafka")
            .marshal().json()
            .to("kafka:results?brokers=" + kafkaBrokers)
            .log("📤 Результат отправлен в Kafka");
    }
}
