#!/usr/bin/env python3
"""
gRPC сервер для обработки команд от Java Gateway
"""

import grpc
import asyncio
import logging
import time
from concurrent import futures

# Добавляем путь к сгенерированному коду
from GRPC.Python.generated.v1 import discord_pb2
from GRPC.Python.generated.v1 import discord_pb2_grpc

# Добавляем метрики
from .metrics import record_request, get_metrics_collector, MetricsExporter

logger = logging.getLogger(__name__)


class DiscordServicer(discord_pb2_grpc.DiscordServiceServicer):
    """Реализация gRPC сервиса DiscordService"""

    def __init__(self, bot):
        self.bot = bot
        self.loop = bot.loop if bot else asyncio.get_event_loop()

    def SendCommand(self, request, context):
        """Обработка команды от Java Gateway"""
        start_time = time.time()
        method = 'SendCommand'

        try:
            logger.info(f"📥 gRPC команда: {request.command} от {request.user_id}")

            # Запускаем асинхронную обработку в основном цикле бота
            asyncio.run_coroutine_threadsafe(
                self.bot.process_java_command(
                    request.command,
                    request.url,
                    request.user_id,
                    request.guild_id,
                    request.channel_id
                ),
                self.loop
            )

            # Записываем успешную метрику
            duration_ms = (time.time() - start_time) * 1000
            record_request(method, duration_ms, success=True)

            return discord_pb2.CommandResponse(
                success=True,
                message="Command accepted",
                data={"status": "accepted"}
            )

        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request(method, duration_ms, success=False, error=str(e))
            logger.error(f"Ошибка в SendCommand: {e}")
            raise

    def GetStatus(self, request, context):
        """Получение статуса бота"""
        start_time = time.time()
        method = 'GetStatus'

        try:
            guild_id = request.guild_id
            # Здесь можно добавить реальную логику получения статуса

            duration_ms = (time.time() - start_time) * 1000
            record_request(method, duration_ms, success=True)

            return discord_pb2.StatusResponse(
                playing=False,
                current_track="",
                volume=50,
                queue_length=0
            )

        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request(method, duration_ms, success=False, error=str(e))
            logger.error(f"Ошибка в GetStatus: {e}")
            raise


class GrpcServer:
    """gRPC сервер для Discord бота"""

    def __init__(self, bot, host='0.0.0.0', port=50051):
        self.bot = bot
        self.host = host
        self.port = port
        self.server = None
        self.servicer = None
        self.metrics_exporter = MetricsExporter(get_metrics_collector())

    def start(self):
        """Запуск gRPC сервера"""
        self.server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
        self.servicer = DiscordServicer(self.bot)
        discord_pb2_grpc.add_DiscordServiceServicer_to_server(self.servicer, self.server)
        self.server.add_insecure_port(f'{self.host}:{self.port}')
        self.server.start()
        logger.info(f"🚀 gRPC сервер запущен на {self.host}:{self.port}")

        # Запускаем фоновую задачу для логирования метрик
        asyncio.create_task(self._log_metrics_periodically())
        return self.server

    def stop(self, grace=5):
        """Остановка gRPC сервера"""
        if self.server:
            self.server.stop(grace)
            logger.info("🛑 gRPC сервер остановлен")

    def wait_for_termination(self):
        """Ожидание завершения сервера"""
        if self.server:
            self.server.wait_for_termination()

    async def _log_metrics_periodically(self, interval=60):
        """Периодическое логирование метрик"""
        while True:
            await asyncio.sleep(interval)
            stats = self.metrics_exporter.to_text()
            logger.info(f"\n{stats}")

    def get_metrics(self, format='text'):
        """Получить метрики в указанном формате"""
        if format == 'prometheus':
            return self.metrics_exporter.to_prometheus()
        elif format == 'json':
            return self.metrics_exporter.to_json()
        else:
            return self.metrics_exporter.to_text()


def start_grpc_server(bot, host='0.0.0.0', port=50051):
    """Удобная функция запуска сервера"""
    server = GrpcServer(bot, host, port)
    server.start()
    return server