#!/usr/bin/env python3
"""
gRPC клиент для связи с Java Gateway
"""

import grpc
from concurrent import futures
import logging

from GRPC.Python.server.server import GrpcServer

# Добавляем путь к сгенерированному коду
from GRPC.Python.generated.v1 import discord_pb2
from GRPC.Python.generated.v1 import discord_pb2_grpc

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ========== 1. КЛИЕНТ (отправляет в Java) ==========

class AudioGrpcClient:
    """gRPC клиент для отправки команд в Java Gateway"""

    def __init__(self, host='localhost', port=50053):
        self.channel = grpc.insecure_channel(f'{host}:{port}')
        self.stub = discord_pb2_grpc.DiscordServiceStub(self.channel)
        logger.info(f"✅ Клиент JavaGateway подключен к {host}:{port}")

    def send_command(self, command, user_id, guild_id, url='', channel_id='', options=None):
        """Отправить команду в Java Gateway"""
        request = discord_pb2.CommandRequest(
            command=command,
            url=url,
            user_id=user_id,
            guild_id=guild_id,
            channel_id=channel_id,
            options=options or {}
        )
        response = self.stub.SendCommand(request)
        return {
            'success': response.success,
            'message': response.message,
            'data': dict(response.data)
        }

    def get_status(self, guild_id):
        """Получить статус из Java Gateway"""
        request = discord_pb2.StatusRequest(guild_id=guild_id)
        response = self.stub.GetStatus(request)
        return {
            'playing': response.playing,
            'current_track': response.current_track,
            'volume': response.volume,
            'queue_length': response.queue_length
        }

    def close(self):
        """Закрыть соединение"""
        self.channel.close()


# ========== 2. СЕРВЕР (принимает от Java) ==========

class JavaCommandHandler(discord_pb2_grpc.DiscordServiceServicer):
    """Обработчик команд от Java Gateway"""

    def __init__(self, bot_callback=None):
        self.bot_callback = bot_callback

    def SendCommand(self, request, context):
        """Java отправил команду"""
        logger.info(f"📥 Java -> Python: команда {request.command}")
        
        if self.bot_callback:
            try:
                result = self.bot_callback(
                    command=request.command,
                    user_id=request.user_id,
                    guild_id=request.guild_id,
                    channel_id=request.channel_id,
                    url=request.url,
                    options=dict(request.options)
                )
                return discord_pb2.CommandResponse(
                    success=result.get('success', True),
                    message=result.get('message', 'OK'),
                    data=result.get('data', {})
                )
            except Exception as e:
                logger.error(f"Ошибка: {e}")
                return discord_pb2.CommandResponse(
                    success=False,
                    message=str(e)
                )
        
        return discord_pb2.CommandResponse(success=True, message="OK")

    def GetStatus(self, request, context):
        """Java запросил статус"""
        return discord_pb2.StatusResponse(
            playing=False,
            current_track="",
            volume=50,
            queue_length=0
        )

    def HealthCheck(self, request, context):
        """Проверка здоровья"""
        return discord_pb2.HealthResponse(
            status="healthy",
            message="Python bot is running"
        )


class JavaGatewayClient:
    """gRPC клиент для приема команд от Java Gateway"""

    def __init__(self, host='0.0.0.0', port=50052, bot_callback=None):
        self.host = host
        self.port = port
        self.client = None
        self.bot_callback = bot_callback

    def start(self):
        """Запустить клиент"""
        self.client = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
        
        discord_pb2_grpc.add_DiscordServiceServicer_to_client(
            JavaCommandHandler(self.bot_callback),
            self.client
        )
        
        self.client.add_insecure_port(f'{self.host}:{self.port}')
        self.client.start()
        logger.info(f"✅ Python клиент запущен на {self.host}:{self.port}")
        logger.info("   Ожидает команды от Java Gateway...")
        return self

    def stop(self):
        """Остановить клиент"""
        if self.client:
            self.client.stop(5)
            logger.info("🔌 Python клиент остановлен")

    def wait(self):
        """Ожидать завершения"""
        if self.client:
            self.client.wait_for_termination()


# ========== 3. УДОБНЫЙ МОСТ (объединяет клиент и сервер) ==========

class GrpcBridge:
    """
    Полный мост:
    - client: отправляет команды в Java
    - server: принимает команды от Java
    """

    def __init__(self, java_host='localhost', java_port=8082,
                 python_host='0.0.0.0', python_port=50052,
                 audio_port=50053, bot_callback=None):
        self.server = GrpcServer(python_host, python_port, audio_port, bot_callback)
        self.client = JavaGatewayClient(java_host, java_port)
        self.host = java_host
        self.port = java_port          # для команд от Java
        self.audio_port = audio_port  # для аудио-команд в Java
        self.bot_callback = bot_callback

    def start_server(self):
        """Запустить сервер (приём от Java)"""
        self.server.start()
        return self

    def send_to_java(self, command, user_id, guild_id, url='', channel_id='', options=None):
        """Отправить команду в Java"""
        return self.client.send_command(command, user_id, guild_id, url, channel_id, options)

    def get_status_from_java(self, guild_id):
        """Получить статус из Java"""
        return self.client.get_status(guild_id)

    def wait(self):
        """Ожидать завершения"""
        self.server.wait()

    def shutdown(self):
        """Остановить всё"""
        self.client.close()
        self.server.stop()