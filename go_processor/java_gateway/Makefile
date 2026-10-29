# Java Gateway Makefile

# Конфигурация
PORT ?= 8080
JAR_FILE ?= java-gateway.jar
BUILD_DIR ?= target

.PHONY: help
help:
	@echo "🎵 Java Gateway - Makefile"
	@echo "======================================="
	@echo "Usage: make [target]"
	@echo ""
	@echo "Development:"
	@echo "  deps          - Установить зависимости"
	@echo "  compile       - Скомпилировать проект"
	@echo "  build         - Собрать JAR файл"
	@echo "  run           - Запустить сервер"
	@echo "  test          - Запустить тесты"
	@echo "  format        - Отформатировать код"
	@echo ""
	@echo "Docker:"
	@echo "  docker-build  - Собрать Docker образ"
	@echo "  docker-run    - Запустить Docker контейнер"
	@echo "  docker-stop   - Остановить Docker контейнер"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean         - Очистить артефакты сборки"

.PHONY: deps
deps:
	@echo "📦 Installing Maven dependencies..."
	mvn dependency:resolve
	@echo "✅ Dependencies installed"

.PHONY: compile
compile:
	@echo "🔧 Compiling Java project..."
	mvn compile
	@echo "✅ Compilation complete"

.PHONY: build
build:
	@echo "📦 Building JAR file..."
	mvn package -DskipTests
	@echo "✅ JAR built: $(BUILD_DIR)/$(JAR_FILE)"

.PHONY: run
run:
	@echo "🚀 Starting Java Gateway on port $(PORT)..."
	java -jar $(BUILD_DIR)/$(JAR_FILE)

.PHONY: test
test:
	@echo "🧪 Running tests..."
	mvn test

.PHONY: format
format:
	@echo "📝 Formatting code..."
	mvn spotless:apply

.PHONY: docker-build
docker-build:
	@echo "🐳 Building Docker image..."
	docker build -t java-gateway .

.PHONY: docker-run
docker-run:
	@echo "🐳 Running Docker container..."
	docker run -d -p $(PORT):$(PORT) --name java-gateway java-gateway

.PHONY: docker-stop
docker-stop:
	@echo "🛑 Stopping Docker container..."
	docker stop java-gateway
	docker rm java-gateway

.PHONY: clean
clean:
	@echo "🧹 Cleaning build artifacts..."
	mvn clean
