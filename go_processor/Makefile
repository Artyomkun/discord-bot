# Go Audio Processor Makefile

# Конфигурация
PORT ?= 8081
BINARY ?= go_processor
BUILD_DIR ?= build

.PHONY: help
help:
	@echo "🎵 Go Audio Processor - Makefile"
	@echo "======================================="
	@echo "Usage: make [target]"
	@echo ""
	@echo "Development:"
	@echo "  deps          - Установить зависимости"
	@echo "  build         - Собрать проект"
	@echo "  run           - Запустить сервер"
	@echo "  test          - Запустить тесты"
	@echo "  lint          - Проверить код линтером"
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
	@echo "📦 Installing Go dependencies..."
	go mod tidy
	@echo "✅ Dependencies installed"

.PHONY: build
build:
	@echo "🔧 Building Go processor..."
	mkdir -p $(BUILD_DIR)
	GOOS=linux GOARCH=amd64 go build -o $(BUILD_DIR)/$(BINARY) main.go
	@echo "✅ Build complete: $(BUILD_DIR)/$(BINARY)"

.PHONY: run
run:
	@echo "🚀 Starting Go processor on port $(PORT)..."
	./$(BUILD_DIR)/$(BINARY)

.PHONY: test
test:
	@echo "🧪 Running tests..."
	go test ./...

.PHONY: lint
lint:
	@echo "🔍 Running linter..."
	go vet ./...

.PHONY: format
format:
	@echo "📝 Formatting code..."
	gofmt -w .

.PHONY: docker-build
docker-build:
	@echo "🐳 Building Docker image..."
	docker build -t go-audio-processor .

.PHONY: docker-run
docker-run:
	@echo "🐳 Running Docker container..."
	docker run -d -p $(PORT):$(PORT) --name go-audio-processor go-audio-processor

.PHONY: docker-stop
docker-stop:
	@echo "🛑 Stopping Docker container..."
	docker stop go-audio-processor
	docker rm go-audio-processor

.PHONY: clean
clean:
	@echo "🧹 Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
