# PostgreSQL для Miku Music Bot
FROM postgres:15-alpine

# Переменные окружения
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=password
ENV POSTGRES_DB=music_bot

# Скрипты инициализации
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql

# Копируем create_users_table.sql только если файл существует
COPY create_users_table.sql /docker-entrypoint-initdb.d/create_users_table.sql

# Порт
EXPOSE 5432

# Volume для данных
VOLUME ["/var/lib/postgresql/data"]

# Healthcheck
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s \
    CMD pg_isready -U postgres || exit 1