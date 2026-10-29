.PHONY: pg-up pg-down pg-build pg-clean pg-logs pg-reset pg-shell pg-status

# Конфигурация
PG_CONTAINER ?= miku-postgres
PG_USER ?= postgres
PG_PORT ?= 5432
DOCKER_COMPOSE ?= docker-compose

pg-build:
	@echo "🐘 Building PostgreSQL image..."
	$(DOCKER_COMPOSE) build

pg-up:
	@echo "🚀 Starting PostgreSQL..."
	$(DOCKER_COMPOSE) up -d
	@echo "⏳ Waiting for PostgreSQL to be ready..."
	@for i in 1 2 3 4 5; do \
		docker exec $(PG_CONTAINER) pg_isready -U $(PG_USER) && break || \
		(echo "Waiting for PostgreSQL... ($$i/5)" && sleep 2); \
	done
	@docker exec $(PG_CONTAINER) pg_isready -U $(PG_USER) && \
		echo "✅ PostgreSQL ready on localhost:$(PG_PORT)" || \
		echo "⚠️ PostgreSQL may not be ready"

pg-down:
	@echo "🛑 Stopping PostgreSQL..."
	$(DOCKER_COMPOSE) down

pg-clean:
	@echo "🧹 Removing PostgreSQL data volume..."
	$(DOCKER_COMPOSE) down -v

pg-reset: pg-clean pg-up
	@echo "🔄 PostgreSQL reset complete"

pg-logs:
	@echo "📄 PostgreSQL logs:"
	docker logs -f $(PG_CONTAINER)

pg-shell:
	@echo "🐚 Connecting to PostgreSQL shell..."
	docker exec -it $(PG_CONTAINER) psql -U $(PG_USER)

pg-status:
	@echo "📊 PostgreSQL status:"
	@docker ps --filter "name=$(PG_CONTAINER)" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "📈 Database stats:"
	@docker exec $(PG_CONTAINER) psql -U $(PG_USER) -c "SELECT datname, numbackends, xact_commit, xact_rollback, blks_hit, blks_read FROM pg_stat_database WHERE datname = 'miku';" 2>/dev/null || echo "Database 'miku' not found"

pg-backup:
	@echo "💾 Backing up database..."
	@mkdir -p backups
	@docker exec $(PG_CONTAINER) pg_dump -U $(PG_USER) miku > backups/miku_$$(date +%Y%m%d_%H%M%S).sql
	@echo "✅ Backup saved to backups/"

pg-restore:
	@echo "📀 Restoring database from $${FILE}..."
	@if [ -z "$$FILE" ]; then \
		echo "Usage: make pg-restore FILE=path/to/backup.sql"; \
		exit 1; \
	fi
	@cat $$FILE | docker exec -i $(PG_CONTAINER) psql -U $(PG_USER) miku
	@echo "✅ Restore complete"

pg-health:
	@echo "🏥 PostgreSQL health check:"
	@docker exec $(PG_CONTAINER) pg_isready -U $(PG_USER)
	@docker inspect $(PG_CONTAINER) | grep -A 5 "Health" || echo "No health check configured"

# Поддержка GPU (если PostgreSQL использует GPU для аналитики)
pg-gpu:
	@echo "🎮 Checking GPU availability for PostgreSQL..."
	@docker run --rm --gpus all nvidia/cuda:12.2-base-ubuntu22.04 nvidia-smi 2>/dev/null && \
		echo "✅ GPU available for PostgreSQL extensions" || \
		echo "⚠️ No GPU available"

# Расширенная помощь
help:
	@echo "PostgreSQL Makefile targets:"
	@echo "  pg-build   - Build custom image"
	@echo "  pg-up      - Start PostgreSQL"
	echo "  pg-down    - Stop PostgreSQL"
	@echo "  pg-clean   - Remove container and volumes"
	@echo "  pg-reset   - Full reset (clean + up)"
	@echo "  pg-logs    - View logs"
	@echo "  pg-shell   - Open psql shell"
	@echo "  pg-status  - Show status and stats"
	@echo "  pg-backup  - Dump database"
	@echo "  pg-restore FILE=... - Restore from backup"
	@echo "  pg-health  - Check health status"
	@echo "  pg-gpu     - Check GPU for analytical extensions"

# Установка по умолчанию
default: pg-status