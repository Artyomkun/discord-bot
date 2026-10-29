#!/usr/bin/env python3
"""
Discord Music Bot - Python Client
Основной бот для Discord, интегрированный с Java Gateway и Go/Elixir сервисами
"""

import os
import asyncio
import discord
from discord.ext import commands
import requests
import logging
import psycopg2
from dotenv import load_dotenv
from commands.music import MusicCommands
from commands.queue import QueueCommands
from utils.discord_client import DiscordClient
import threading
import sys

# Добавляем путь к gRPC модулям
sys.path.insert(0, '/mnt/c/Мои проекты/Kodland/elixir_music_bot')
sys.path.insert(0, '/mnt/c/Мои проекты/Kodland/elixir_music_bot/GRPC/Python')
from GRPC.Python.generated.v1 import discord_pb2_grpc
from GRPC.Python.generated.v1 import discord_pb2
import grpc
from concurrent import futures

# Загрузка переменных окружения
load_dotenv()

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DiscordServicer(discord_pb2_grpc.DiscordServiceServicer):
    """gRPC сервис для обработки команд от Java Gateway"""
    
    def __init__(self, bot):
        self.bot = bot

    def SendCommand(self, request, context):
        """Обработка команды от Java Gateway через gRPC"""
        logger.info(f"📥 gRPC команда: {request.command} от {request.user_id}")
        asyncio.run_coroutine_threadsafe(
            self.bot.process_java_command(
                request.command,
                request.url,
                request.user_id,
                request.guild_id,
                request.channel_id
            ),
            self.bot.loop
        )
        
        return discord_pb2.CommandResponse(
            success=True,
            message="Command accepted",
            data={"status": "accepted"}
        )

    def GetStatus(self, request, context):
        """Получение статуса бота"""
        guild_id = request.guild_id
        return discord_pb2.StatusResponse(
            playing=False,
            current_track="",
            volume=50,
            queue_length=0
        )


class MusicBot(commands.Bot):
    """Основной класс Discord бота для музыки"""

    def __init__(self):
        # Настройки intents для Discord
        intents = discord.Intents.default()
        intents.message_content = True
        intents.voice_states = True
        intents.guilds = True
        intents.messages = True

        # Инициализация бота
        super().__init__(
            command_prefix='!',
            intents=intents,
            help_command=None  # Отключаем стандартную помощь
        )

        # Конфигурация
        self.java_gateway_url = os.getenv('JAVA_GATEWAY_URL', 'http://localhost:8080')
        self.grpc_port = int(os.getenv('GRPC_PORT', '50051'))
        try:
            self.python_api_port = int(os.getenv('PYTHON_API_PORT', '5000'))
        except ValueError:
            self.python_api_port = 5000

        # Подключение к базе данных
        self.db_conn = None
        try:
            db_url = os.getenv('DATABASE_URL', 'postgresql://postgres:password@localhost:5432/music_bot')
            self.db_conn = psycopg2.connect(db_url)
            logger.info("✅ Database connected")
        except Exception as e:
            logger.error(f"❌ Failed to connect to database: {e}")

        # Клиенты для связи с другими сервисами
        self.discord_client = DiscordClient(self)
        self.music_commands = MusicCommands(self)
        self.queue_commands = QueueCommands(self)

        # Состояние бота
        self.is_ready = False
        self.connected_guilds = set()
        self.grpc_server = None

        logger.info("🎵 MusicBot инициализирован")

    def start_grpc_server(self):
        """Запуск gRPC сервера в отдельном потоке"""
        server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
        discord_pb2_grpc.add_DiscordServiceServicer_to_server(
            DiscordServicer(self), server
        )
        server.add_insecure_port(f'[::]:{self.grpc_port}')
        server.start()
        logger.info(f"🚀 gRPC сервер запущен на порту {self.grpc_port}")
        return server

    async def setup_hook(self):
        """Настройка хуков перед запуском"""
        logger.info("🔧 Настройка хуков...")

        # Регистрация команд
        await self.add_cog(self.music_commands)
        await self.add_cog(self.queue_commands)
        loop = asyncio.get_event_loop()
        self.grpc_server = await loop.run_in_executor(None, self.start_grpc_server)

        logger.info("✅ Хуки настроены")

    async def on_ready(self):
        """Событие при готовности бота"""
        self.is_ready = True
        logger.info(f"🤖 Бот {self.user} готов!")
        logger.info(f"🌐 Подключен к {len(self.guilds)} серверам")

        # Обновляем список подключенных серверов
        self.connected_guilds = {guild.id for guild in self.guilds}
        await self.check_java_gateway()
        await self.start_api_server()

    async def on_guild_join(self, guild):
        """Событие при присоединении к серверу"""
        self.connected_guilds.add(guild.id)
        logger.info(f"➕ Присоединились к серверу: {guild.name} ({guild.id})")

        await self.register_guild(guild)

    async def on_guild_remove(self, guild):
        """Событие при выходе с сервера"""
        self.connected_guilds.discard(guild.id)
        logger.info(f"➖ Вышли с сервера: {guild.name} ({guild.id})")

    async def check_java_gateway(self):
        """Проверка подключения к Java Gateway"""
        try:
            response = requests.get(f"{self.java_gateway_url}/health", timeout=5)
            if response.status_code == 200:
                logger.info("✅ Java Gateway доступен")
                return True
            else:
                logger.warning(f"⚠️ Java Gateway вернул статус {response.status_code}")
                return False
        except Exception as e:
            logger.error(f"❌ Ошибка подключения к Java Gateway: {e}")
            return False

    async def register_guild(self, guild):
        """Регистрация сервера в Java Gateway"""
        try:
            data = {
                "guild_id": str(guild.id),
                "guild_name": guild.name,
                "member_count": guild.member_count,
                "python_bot_connected": True
            }

            response = requests.post(
                f"{self.java_gateway_url}/api/register/guild",
                json=data,
                timeout=10
            )

            if response.status_code == 200:
                logger.info(f"✅ Сервер {guild.name} зарегистрирован в Java Gateway")
            else:
                logger.warning(f"⚠️ Не удалось зарегистрировать сервер {guild.name}")

        except Exception as e:
            logger.error(f"❌ Ошибка регистрации сервера {guild.name}: {e}")

    async def start_api_server(self):
        """Запуск API сервера для связи с Java Gateway"""
        from flask import Flask, request, jsonify

        app = Flask(__name__)

        @app.route('/health', methods=['GET'])
        def health():
            return jsonify({
                "status": "healthy",
                "service": "python_discord_bot",
                "guilds_connected": len(self.connected_guilds)
            })

        @app.route('/api/command', methods=['POST'])
        def handle_command():
            """Обработка команд от Java Gateway"""
            try:
                data = request.get_json()

                command = data.get('command')
                url = data.get('url')
                user_id = data.get('user_id')
                guild_id = data.get('guild_id')

                logger.info(
                    f"📥 Получена команда от Java: {command} для пользователя {user_id}"
                )

                asyncio.run_coroutine_threadsafe(
                    self.process_java_command(command, url, user_id, guild_id),
                    self.loop
                )

                return jsonify({
                    "status": "accepted",
                    "command": command,
                    "message": "Command forwarded to Discord bot"
                })

            except Exception as e:
                logger.error(f"❌ Ошибка обработки команды от Java: {e}")
                return jsonify({
                    "status": "error",
                    "error": str(e)
                }), 500

        @app.route('/status', methods=['GET'])
        def status():
            return jsonify({
                "bot_ready": self.is_ready,
                "guilds_connected": len(self.connected_guilds),
                "java_gateway_url": self.java_gateway_url,
                "grpc_port": self.grpc_port,
                "uptime": "unknown"
            })

        # Запуск сервера в отдельном потоке
        server_thread = threading.Thread(
            target=lambda: app.run(host='0.0.0.0', port=self.python_api_port, debug=False)
        )
        server_thread.daemon = True
        server_thread.start()

        logger.info(f"🚀 API сервер запущен на порту {self.python_api_port}")

    async def process_java_command(self, command: str, url: str, user_id: str, guild_id: str, channel_id: str = ""):
        """Обработка команды от Java Gateway"""
        try:
            # Находим пользователя и сервер
            user = self.get_user(int(user_id))
            guild = self.get_guild(int(guild_id))

            if not user:
                logger.warning(f"⚠️ Пользователь {user_id} не найден")
                return

            if not guild:
                logger.warning(f"⚠️ Сервер {guild_id} не найден")
                return

            logger.info(
                f"🎵 Обработка команды {command} для пользователя {user_id} на сервере {guild_id}"
            )

            try:
                logger.info(f"🎵 Обработка команды {command} от Java для guild {guild_id}")
                
                # Передаём команду в DiscordClient, где уже есть вся логика
                result = await self.discord_client.process_java_command(
                    command=command,
                    user_id=user_id,
                    guild_id=guild_id,
                    channel_id=channel_id,
                    url=url,
                    options={}
                )
                
                if result.get("success"):
                    logger.info(f"✅ Команда {command} выполнена успешно")
                else:
                    logger.warning(f"⚠️ Ошибка выполнения команды {command}: {result.get('message')}")
                    
            except Exception as e:
                logger.error(f"❌ Ошибка обработки команды {command}: {e}")

        except Exception as e:
            logger.error(f"❌ Ошибка обработки команды {command}: {e}")

    async def send_to_java_gateway(self, endpoint: str, data: dict):
        """Отправка данных в Java Gateway"""
        try:
            url = f"{self.java_gateway_url}{endpoint}"
            response = requests.post(url, json=data, timeout=10)

            if response.status_code == 200:
                return response.json()
            else:
                logger.warning(f"⚠️ Java Gateway вернул {response.status_code}: {response.text}")
                return None

        except Exception as e:
            logger.error(f"❌ Ошибка отправки в Java Gateway: {e}")
            return None


async def main():
    """Главная функция"""
    token = os.getenv('DISCORD_TOKEN')
    if not token:
        logger.error("❌ DISCORD_TOKEN не найден в переменных окружения")
        return

    bot = MusicBot()

    try:
        logger.info("🚀 Запуск Discord бота...")
        await bot.start(token)
    except KeyboardInterrupt:
        logger.info("🛑 Остановка бота...")
        await bot.close()
    except Exception as e:
        logger.error(f"❌ Критическая ошибка: {e}")
        await bot.close()

if __name__ == "__main__":
    asyncio.run(main())