"""
Discord Client Utilities
Утилиты для работы с Discord API
"""

import discord
import logging
from typing import Optional, Dict, List
import time

from GRPC.Python.server import GrpcServer
from GRPC.Python.client import AudioGrpcClient

logger = logging.getLogger(__name__)


class DiscordClient:
    """Клиент для работы с Discord API (только команды и UI)"""

    def __init__(self, bot, use_grpc=True, grpc_host='localhost', grpc_port=50053, 
                    java_callback_host='0.0.0.0', java_callback_port=50052):
        self.bot = bot
        self.command_cooldowns: Dict[str, Dict[int, float]] = {}
        self.user_permissions: Dict[int, Dict[str, bool]] = {}
        self.use_grpc = use_grpc
        self.grpc_client = None
        self.java_server = None
        self.java_callback_port = java_callback_port
        self._running = True

        # Клиент для отправки команд в Java (Python → Java)
        if self.use_grpc:
            try:
                self.grpc_client = AudioGrpcClient(grpc_host, grpc_port)
                logger.info(f"✅ gRPC клиент (Python → Java) подключен к {grpc_host}:{grpc_port}")
            except Exception as e:
                logger.error(f"❌ Ошибка подключения gRPC клиента: {e}")
                self.use_grpc = False

        # Сервер для приёма команд от Java (Java → Python)
        try:
            self.java_server = GrpcServer(
                bot=self,
                host=java_callback_host,
                port=java_callback_port,
                max_workers=5
            )
            self.java_server.start()
            logger.info(f"✅ gRPC сервер (Java → Python) запущен на {java_callback_host}:{java_callback_port}")
        except Exception as e:
            logger.error(f"❌ Ошибка запуска gRPC сервера: {e}")

    async def _send_command_grpc(self, command: str, user_id: str, guild_id: str, **kwargs):
        """Отправка команды через gRPC в Java"""
        try:
            response = self.grpc_client.send_command(
                command=command,
                user_id=user_id,
                guild_id=guild_id,
                url=kwargs.get('url', ''),
                channel_id=kwargs.get('channel_id', ''),
                options=kwargs.get('options', {})
            )
            return {
                "status": "accepted" if response.get('success', False) else "error", 
                "message": response.get('message', 'Unknown error')
            }
        except Exception as e:
            logger.error(f"❌ gRPC ошибка: {e}, падаем на HTTP")
            return await self._send_command_http(command, user_id, guild_id, **kwargs)

    async def _send_command_http(self, command: str, user_id: str, guild_id: str, **kwargs):
        """Отправка команды через HTTP (fallback)"""
        data = {
            "command": command,
            "user_id": user_id,
            "guild_id": guild_id,
            **kwargs
        }
        if hasattr(self.bot, 'send_to_java_gateway'):
            return await self.bot.send_to_java_gateway("/api/command", data)
        else:
            logger.error("❌ bot.send_to_java_gateway не реализован")
            return {"status": "error", "message": "HTTP fallback not available"}

    async def send_command(self, command: str, user_id: str, guild_id: str, **kwargs):
        """Отправка команды (автоматический выбор gRPC или HTTP)"""
        if self.use_grpc and self.grpc_client:
            return await self._send_command_grpc(command, user_id, guild_id, **kwargs)
        else:
            return await self._send_command_http(command, user_id, guild_id, **kwargs)

    # ========== МЕТОД ДЛЯ ОБРАБОТКИ КОМАНД ОТ JAVA ==========

    async def process_java_command(self, command: str, user_id: str, guild_id: str, 
                                    channel_id: str, url: str, options: dict):
        """
        Обработка команды, пришедшей от Java Gateway
        Вызывается из gRPC сервера
        """
        logger.info(f"📥 Java → Discord: команда {command} для guild {guild_id}")
        
        try:
            # Проверяем guild_id
            if not guild_id:
                logger.error("guild_id не указан")
                return {"success": False, "message": "guild_id is required"}
            
            # Получаем гильдию
            guild = self.bot.get_guild(int(guild_id))
            if not guild:
                logger.error(f"Гильдия {guild_id} не найдена")
                return {"success": False, "message": f"Guild {guild_id} not found"}
            
            # Ищем текстовый канал
            channel = await self._find_text_channel(guild, user_id, channel_id)
            
            if not channel:
                logger.error(f"❌ Нет текстовых каналов в гильдии {guild_id}")
                return {"success": False, "message": "No text channels found in this guild"}
            
            # Отправляем сообщение в зависимости от команды
            await self._execute_command_in_channel(channel, command, url, options)
            
            return {"success": True, "message": f"Command {command} executed in {channel.name}"}
            
        except ValueError as e:
            logger.error(f"Ошибка преобразования ID: {e}")
            return {"success": False, "message": f"Invalid ID format: {e}"}
        except Exception as e:
            logger.error(f"Ошибка выполнения команды {command}: {e}")
            return {"success": False, "message": str(e)}

    async def _find_text_channel(self, guild: discord.Guild, user_id: str, channel_id: str) -> Optional[discord.TextChannel]:
        """Найти текстовый канал для отправки сообщения"""
        channel = None
        
        # 1. По channel_id
        if channel_id:
            try:
                channel = guild.get_channel(int(channel_id))
                if channel and isinstance(channel, discord.TextChannel):
                    logger.info(f"✅ Найден канал по ID: {channel.name}")
                    return channel
            except (ValueError, TypeError):
                pass
        
        # 2. По правам пользователя
        if user_id:
            try:
                member = guild.get_member(int(user_id))
                if member:
                    for ch in guild.text_channels:
                        if ch.permissions_for(member).send_messages:
                            channel = ch
                            logger.info(f"✅ Найден канал с правами: {ch.name}")
                            return channel
            except (ValueError, TypeError):
                pass
        
        # 3. Первый текстовый канал
        for ch in guild.text_channels:
            channel = ch
            logger.info(f"⚠️ Использую первый доступный канал: {ch.name}")
            return channel
        
        return None

    async def _execute_command_in_channel(self, channel: discord.TextChannel, command: str, url: str, options: dict):
        """Выполнить команду в канале"""
        
        # Общая функция отправки embed
        async def send_embed(title: str, description: str, color: discord.Color):
            embed = discord.Embed(
                title=title,
                description=description,
                color=color
            )
            await channel.send(embed=embed)
        
        if command == "play":
            await send_embed(
                "🎵 Воспроизведение",
                f"Начинаю воспроизведение: {url}",
                discord.Color.green()
            )
            
        elif command == "stop":
            await send_embed(
                "⏹️ Остановка",
                "Воспроизведение остановлено",
                discord.Color.orange()
            )
            
        elif command == "pause":
            await send_embed(
                "⏸️ Пауза",
                "Воспроизведение приостановлено",
                discord.Color.blue()
            )
            
        elif command == "resume":
            await send_embed(
                "▶️ Возобновление",
                "Воспроизведение возобновлено",
                discord.Color.green()
            )
            
        elif command == "skip":
            await send_embed(
                "⏭️ Пропуск",
                "Трек пропущен",
                discord.Color.blue()
            )
            
        elif command == "volume":
            volume = options.get("volume", 50)
            await send_embed(
                "🔊 Громкость",
                f"Громкость установлена на {volume}%",
                discord.Color.blue()
            )
            
        elif command == "status":
            await send_embed(
                "🎵 Статус",
                "Бот работает",
                discord.Color.green()
            )
            
        elif command == "queue":
            await send_embed(
                "📋 Очередь",
                "Очередь пуста",
                discord.Color.blue()
            )
            
        elif command == "clear":
            await send_embed(
                "🗑️ Очистка",
                "Очередь очищена",
                discord.Color.orange()
            )
            
        elif command == "shuffle":
            await send_embed(
                "🔀 Перемешивание",
                "Очередь перемешана",
                discord.Color.blue()
            )
            
        elif command == "loop":
            mode = options.get("mode", "none")
            await send_embed(
                "🔄 Повтор",
                f"Режим повтора: {mode}",
                discord.Color.blue()
            )
            
        else:
            await send_embed(
                "🤖 Команда",
                f"Получена команда: {command}",
                discord.Color.blue()
            )

    # ========== ОСТАЛЬНЫЕ МЕТОДЫ ==========

    async def get_voice_channel(self, user: discord.User, guild: discord.Guild) -> Optional[discord.VoiceChannel]:
        """Получение голосового канала пользователя"""
        member = guild.get_member(user.id)
        if member and member.voice and member.voice.channel:
            return member.voice.channel
        return None

    async def ensure_voice_connection(self, interaction: discord.Interaction) -> bool:
        """Проверка, что пользователь в голосовом канале и есть права"""
        if not interaction.guild:
            if not interaction.response.is_done():
                await interaction.response.send_message("❌ Эта команда доступна только на серверах!", ephemeral=True)
            return False

        voice_channel = await self.get_voice_channel(interaction.user, interaction.guild)
        if not voice_channel:
            if not interaction.response.is_done():
                await interaction.response.send_message("❌ Вы должны быть в голосовом канале!", ephemeral=True)
            return False

        if not voice_channel.permissions_for(interaction.guild.me).connect:
            if not interaction.response.is_done():
                await interaction.response.send_message("❌ У меня нет прав для подключения к этому каналу!", ephemeral=True)
            return False

        if not voice_channel.permissions_for(interaction.guild.me).speak:
            if not interaction.response.is_done():
                await interaction.response.send_message("❌ У меня нет прав для разговора в этом канале!", ephemeral=True)
            return False

        return True

    def check_permissions(self, user: discord.User, permission: str) -> bool:
        """Проверка разрешений пользователя"""
        if isinstance(user, discord.Member) and user.guild_permissions.administrator:
            return True

        user_perms = self.user_permissions.get(user.id, {})
        return user_perms.get(permission, False)

    def set_user_permission(self, user_id: int, permission: str, value: bool):
        """Установка разрешения для пользователя"""
        if user_id not in self.user_permissions:
            self.user_permissions[user_id] = {}
        self.user_permissions[user_id][permission] = value

    def check_cooldown(self, command: str, user_id: int, cooldown_seconds: float = 3.0) -> bool:
        """Проверка кулдауна команды"""
        now = time.time()

        if command not in self.command_cooldowns:
            self.command_cooldowns[command] = {}

        last_used = self.command_cooldowns[command].get(user_id, 0)

        if now - last_used < cooldown_seconds:
            return False

        self.command_cooldowns[command][user_id] = now
        return True

    async def send_embed_message(self, channel: discord.TextChannel, title: str, description: str = "",
                                color: discord.Color = discord.Color.blue(),
                                fields: List[Dict[str, str]] = None,
                                footer: str = None) -> Optional[discord.Message]:
        """Отправка embed сообщения"""
        try:
            embed = discord.Embed(
                title=title,
                description=description,
                color=color
            )

            if fields:
                for field in fields:
                    embed.add_field(
                        name=field.get('name', ''),
                        value=field.get('value', ''),
                        inline=field.get('inline', True)
                    )

            if footer:
                embed.set_footer(text=footer)

            return await channel.send(embed=embed)

        except Exception as e:
            logger.error(f"❌ Ошибка отправки embed сообщения: {e}")
            return None

    async def send_error_message(self, interaction: discord.Interaction, error: str):
        """Отправка сообщения об ошибке"""
        try:
            embed = discord.Embed(
                title="❌ Ошибка",
                description=error,
                color=discord.Color.red()
            )

            if interaction.response.is_done():
                await interaction.followup.send(embed=embed, ephemeral=True)
            else:
                await interaction.response.send_message(embed=embed, ephemeral=True)

        except Exception as e:
            logger.error(f"❌ Ошибка отправки сообщения об ошибке: {e}")

    async def send_success_message(self, interaction: discord.Interaction, message: str):
        """Отправка сообщения об успехе"""
        try:
            embed = discord.Embed(
                title="✅ Успешно",
                description=message,
                color=discord.Color.green()
            )

            if interaction.response.is_done():
                await interaction.followup.send(embed=embed, ephemeral=True)
            else:
                await interaction.response.send_message(embed=embed, ephemeral=True)

        except Exception as e:
            logger.error(f"❌ Ошибка отправки сообщения об успехе: {e}")

    def format_duration(self, seconds: float) -> str:
        """Форматирование длительности в читаемый вид"""
        if seconds <= 0:
            return "0:00"
        hours, remainder = divmod(int(seconds), 3600)
        minutes, seconds = divmod(remainder, 60)

        if hours > 0:
            return f"{hours}:{minutes:02d}:{seconds:02d}"
        else:
            return f"{minutes}:{seconds:02d}"

    def format_track_info(self, title: str, artist: str = None, duration: float = None) -> str:
        """Форматирование информации о треке"""
        info = f"**{title}**"
        if artist:
            info += f" by **{artist}**"
        if duration:
            info += f" `[{self.format_duration(duration)}]`"
        return info

    async def cleanup_old_messages(self, channel: discord.TextChannel, limit: int = 50):
        """Очистка старых сообщений бота"""
        try:
            def is_bot_message(message):
                return message.author == self.bot.user

            deleted = await channel.purge(limit=limit, check=is_bot_message)
            logger.info(f"🧹 Очищено {len(deleted)} сообщений бота в канале {channel.name}")

        except Exception as e:
            logger.error(f"❌ Ошибка очистки сообщений: {e}")

    def get_guild_settings(self, guild_id: int) -> Dict:
        """Получение настроек сервера"""
        return {
            'max_queue_size': 100,
            'max_track_duration': 3600,
            'default_volume': 50,
            'allow_duplicates': False,
            'auto_disconnect': True,
            'auto_disconnect_delay': 300
        }

    def close_grpc(self):
        """Закрыть gRPC соединение"""
        if self.grpc_client:
            self.grpc_client.close()
            logger.info("🔌 gRPC соединение закрыто")
        
        if self.java_server:
            self.java_server.stop()
            logger.info("🔌 gRPC сервер остановлен")