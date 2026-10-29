# Python Discord Bot Makefile

PYTHON ?= python3.13
REQUIREMENTS ?= requirements.txt

PROJECT_ROOT := $(realpath ../../../../../../..)

VENV_DIR         := $(PROJECT_ROOT)/GRPC/Python/venv
ELIXIR_DIR       := $(PROJECT_ROOT)/music_core
GO_PROCESSOR_DIR := $(PROJECT_ROOT)/go_processor
JAVA_GATEWAY_DIR := $(PROJECT_ROOT)/go_processor/java_gateway
PYTHON_DIR       := .
GRPC_GENERATED_DIR := $(PROJECT_ROOT)/GRPC/Python/generated
GRPC_GENERATED_V1   := $(GRPC_GENERATED_DIR)/v1
GRPC_PYTHON_DIR := $(PROJECT_ROOT)/GRPC/Python
GRPC_DIR := $(PROJECT_ROOT)/GRPC

SHELL := /bin/bash

.PHONY: help venv deps run run-all stop-all

.PHONY: help
help:
	@echo "🎵 Python Discord Bot — Makefile"
	@echo "=================================="
	@echo "Разработка:"
	@echo "  venv      — создать виртуальное окружение"
	@echo "  deps      — установить зависимости"
	@echo "  run       — запустить бота"
	@echo "  test      — запустить тесты (pytest)"
	@echo "  lint      — проверить код (flake8)"
	@echo "  format    — отформатировать код (black)"
	@echo "  clean     — удалить venv и артефакты"
	@echo ""
	@echo "Все компоненты Elixir + Go + Java + Python:"
	@echo "  deps-all  — установить зависимости во всех компонентах"
	@echo "  run-all   — запустить всё в tmux сессии 'music_bot'"
	@echo "  stop-all  — остановить всё"
	@echo "  clean-all — очистить все компоненты"
	@echo ""
	@echo "PostgreSQL:"
	@echo "  pg-start  — запустить PostgreSQL"
	@echo "  pg-stop   — остановить PostgreSQL"

venv:
	$(PYTHON) -m venv $(VENV_DIR)

deps:
	source $(VENV_DIR)/bin/activate && pip install -r $(REQUIREMENTS)

run:
	export PROJECT_ROOT="$(PROJECT_ROOT)"; \
	export ELIXIR_DIR="$(ELIXIR_DIR)"; \
	export GO_PROCESSOR_DIR="$(GO_PROCESSOR_DIR)"; \
	export JAVA_GATEWAY_DIR="$(JAVA_GATEWAY_DIR)"; \
	export PYTHON_DIR="$(PYTHON_DIR)"; \
	export PYTHONPATH="$(GRPC_DIR):$(GRPC_PYTHON_DIR):$(GRPC_GENERATED_DIR):$(GRPC_GENERATED_V1):$${PYTHONPATH}"; \
	./run-all.sh python

run-all:
	export PROJECT_ROOT="$(PROJECT_ROOT)"; \
	export ELIXIR_DIR="$(ELIXIR_DIR)"; \
	export GO_PROCESSOR_DIR="$(GO_PROCESSOR_DIR)"; \
	export JAVA_GATEWAY_DIR="$(JAVA_GATEWAY_DIR)"; \
	export PYTHON_DIR="$(PYTHON_DIR)"; \
	export PYTHONPATH="$(GRPC_DIR):$(GRPC_PYTHON_DIR):$(GRPC_GENERATED_DIR):$(GRPC_GENERATED_V1):$${PYTHONPATH}"; \
	./run-all.sh

stop-all:
	tmux kill-session -t music_bot 2>/dev/null || true