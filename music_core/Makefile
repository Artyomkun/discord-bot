# Elixir Music Core Makefile

# Конфигурация
PORT ?= 4000
MIX_ENV ?= dev

.PHONY: help
help:
	@echo "🎵 Elixir Music Core - Makefile"
	@echo "======================================="
	@echo "Usage: make [target]"
	@echo ""
	@echo "Development:"
	@echo "  deps          - Установить зависимости"
	@echo "  compile       - Скомпилировать проект"
	@echo "  run           - Запустить сервер"
	@echo "  test          - Запустить тесты"
	@echo "  lint          - Проверить код линтером"
	@echo "  format        - Отформатировать код"
	@echo ""
	@echo "Database:"
	@echo "  db-setup      - Настройка базы данных"
	@echo "  db-reset      - Сброс базы данных"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean         - Очистить артефакты сборки"
	@echo "  clean-all     - Полная очистка"

.PHONY: deps
deps:
	@echo "📦 Installing Elixir dependencies..."
	mix deps.get
	@echo "✅ Dependencies installed"

.PHONY: compile
compile:
	@echo "🔧 Compiling Elixir project..."
	mix compile
	@echo "✅ Compilation complete"

.PHONY: run
run:
	@echo "🚀 Starting Elixir server on port $(PORT)..."
	MIX_ENV=$(MIX_ENV) mix run --no-halt

.PHONY: test
test:
	@echo "🧪 Running tests..."
	mix test

.PHONY: lint
lint:
	@echo "🔍 Running linter..."
	mix credo --strict

.PHONY: format
format:
	@echo "📝 Formatting code..."
	mix format

.PHONY: db-setup
db-setup:
	@echo "🗄️ Setting up database..."
	mix ecto.setup

.PHONY: db-reset
db-reset:
	@echo "🔄 Resetting database..."
	mix ecto.reset

.PHONY: clean
clean:
	@echo "🧹 Cleaning build artifacts..."
	mix clean

.PHONY: clean-all
clean-all:
	@echo "🧹 Full cleanup..."
	rm -rf _build deps
