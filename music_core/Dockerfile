# Elixir Music Core - Production Dockerfile
FROM elixir:1.17

# Системные зависимости
RUN apt-get update && apt-get install -y \
    # Основные инструменты
    build-essential \
    git \
    curl \
    wget \
    vim \
    htop \
    net-tools \
    iputils-ping \
    telnet \
    # Аудио
    ffmpeg \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libavdevice-dev \
    libswresample-dev \
    libswscale-dev \
    portaudio19-dev \
    libasound2-dev \
    libpulse-dev \
    libmp3lame-dev \
    libopus-dev \
    libvorbis-dev \
    # Rust NIF
    libssl-dev \
    pkg-config \
    # gRPC/Protobuf
    protobuf-compiler \
    libprotobuf-dev \
    # С/C++
    gcc g++ make \
    cmake \
    # БД
    libpq-dev \
    # Криптография
    libsodium-dev \
    # Изображения (для обложек треков)
    libjpeg-dev \
    libpng-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Установка Rust (для NIF)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

# Копируем ВСЁ (включая скомпилированные deps и _build)
COPY . .

# Порты (ВСЕ, как в docker-compose)
# Elixir
# 4000 - HTTP API
# 4001 - WebSocket
# 4002 - gRPC сервер
# 50052 - gRPC клиент (Elixir → другие сервисы)
# 8080 - Prometheus metrics
# Внешние сервисы (для информации)
# 5432 - PostgreSQL
# 6379 - Redis
# 8082 - Go gRPC сервер
# 8081 - Java gRPC сервер
# 8083 - Java gRPC клиент
# 5000 - Python HTTP
# 50051 - Python gRPC сервер
# 50053 - Python gRPC клиент
EXPOSE 4000 4001 4002 50052 8080 5432 6379 8082 8081 8083 5000 50051 50053

# Переменные окружения для production
ENV MIX_ENV=prod

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1

# Запуск
CMD ["mix", "run", "--no-halt"]