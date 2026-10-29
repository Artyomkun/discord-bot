# Используем базовый образ Astra Linux UBI
FROM registry.astralinux.ru/library/astra/ubi18:latest

# 1. Системные зависимости
RUN apt-get update && apt-get install -y --no-install-recommends \
    tar \
    ca-certificates \
    gcc \
    g++ \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Установка Go 1.25.0
COPY go1.25.0.linux-amd64.tar.gz /tmp/
RUN tar -C /usr/local -xzf /tmp/go1.25.0.linux-amd64.tar.gz \
    && rm /tmp/go1.25.0.linux-amd64.tar.gz
ENV PATH=$PATH:/usr/local/go/bin

# 3. Установка ONNX Runtime
COPY onnxruntime-linux-x64-1.20.1.tgz /tmp/
RUN tar -xzf /tmp/onnxruntime-linux-x64-1.20.1.tgz -C /tmp \
    && cp /tmp/onnxruntime-linux-x64-1.20.1/lib/*.so* /usr/local/lib/ \
    && cp -r /tmp/onnxruntime-linux-x64-1.20.1/include/* /usr/local/include/ \
    && rm -rf /tmp/onnxruntime-linux-x64-1.20.1*
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/local.conf && ldconfig

WORKDIR /app

# 4. Копируем код и vendor
COPY go.mod go.sum ./
COPY . .

# 6. Сборка с vendor режимом
ENV CGO_ENABLED=1
RUN go mod vendor && go build -mod=vendor -o main .

EXPOSE 8081
CMD ["./main"]