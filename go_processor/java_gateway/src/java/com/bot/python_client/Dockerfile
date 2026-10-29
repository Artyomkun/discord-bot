FROM python:3.13

WORKDIR /app

COPY requirements.txt ./

RUN pip install --no-cache-dir -r requirements.txt
RUN pip install --upgrade pip

COPY . .

# Порты
# 4000 - Elixir HTTP API
# 4002 - Elixir gRPC сервер
# 8081 - Java gRPC сервер
# 8083 - Java gRPC клиент
# 50051 - Python gRPC сервер (Discord бот)
# 50053 - Python gRPC клиент
EXPOSE 4000 4002 8081 8083 50051 50053

CMD ["python", "bot.py"]