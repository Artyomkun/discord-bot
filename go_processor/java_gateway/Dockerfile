FROM eclipse-temurin:17-jdk-alpine

WORKDIR /app

# Обновление сертификатов и установка Maven + curl
RUN apk update && apk add --no-cache ca-certificates tzdata
RUN apk add --no-cache maven curl

# Копируем pom.xml и скачиваем зависимости
COPY pom.xml ./
RUN mvn dependency:go-offline -B

# Копируем исходники
COPY . .

# Сборка
RUN mvn clean package -DskipTests

# Скрипт ожидания Kafka
COPY wait-for-kafka.sh /wait-for-kafka.sh
RUN chmod +x /wait-for-kafka.sh

EXPOSE 8080
EXPOSE 50050

# Ждём Kafka перед запуском
CMD ["/wait-for-kafka.sh", "kafka:9092", "--", "java", "-jar", "target/*.jar"]