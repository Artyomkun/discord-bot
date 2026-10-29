"""
Queue Commands Cog
Команды для управления очередью воспроизведения
"""

import discord
from discord import app_commands
from discord.ext import commands
import logging
import grpc
import os

# Добавляем путь к gRPC модулям
from GRPC.Python.generated.v1 import discord_pb2_grpc
from GRPC.Python.generated.v1 import discord_pb2

logger = logging.getLogger(__name__)

class QueueCommands(commands.Cog):
    """Ког для команд управления очередью"""

    def __init__(self, bot):
        self.bot = bot
        self.discord_client = bot.discord_client
        self.use_grpc = os.getenv('USE_GRPC', 'false').lower() == 'true'
        self.grpc_channel = None
        
        if self.use_grpc:
            try:
                self.grpc_channel = grpc.insecure_channel('localhost:50051')
                self.grpc_stub = discord_pb2_grpc.DiscordServiceStub(self.grpc_channel)
                logger.info("✅ gRPC клиент инициализирован")
            except Exception as e:
                logger.error(f"❌ Ошибка инициализации gRPC: {e}")
                self.use_grpc = False

    async def _send_command(self, command: str, user_id: str, guild_id: str, **kwargs):
        """Отправка команды через HTTP или gRPC"""
        if self.use_grpc and self.grpc_channel:
            try:
                request = discord_pb2.CommandRequest(
                    command=command,
                    url=kwargs.get('url', ''),
                    user_id=user_id,
                    guild_id=guild_id,
                    channel_id=kwargs.get('channel_id', ''),
                    options=kwargs.get('options', {})
                )
                response = self.grpc_stub.SendCommand(request)
                return {"status": "accepted" if response.success else "error", "message": response.message}
            except Exception as e:
                logger.error(f"❌ gRPC ошибка: {e}, падаем на HTTP")
                return await self._send_http_command(command, user_id, guild_id, **kwargs)
        else:
            return await self._send_http_command(command, user_id, guild_id, **kwargs)

    async def _send_http_command(self, command: str, user_id: str, guild_id: str, **kwargs):
        """Отправка команды через HTTP"""
        data = {
            "command": command,
            "user_id": user_id,
            "guild_id": guild_id,
            **kwargs
        }
        return await self.bot.send_to_java_gateway("/api/command", data)

    @app_commands.command(name="queue", description="Показать текущую очередь воспроизведения")
    async def queue(self, interaction: discord.Interaction):
        """Показать очередь воспроизведения"""
        try:
            response = await self._send_command(
                "queue_status",
                str(interaction.user.id),
                str(interaction.guild.id)
            )

            if response and response.get("queue"):
                queue_data = response["queue"]
                tracks = queue_data.get("tracks", [])

                if not tracks:
                    embed = discord.Embed(
                        title="📋 Очередь воспроизведения",
                        description="Очередь пуста",
                        color=discord.Color.blue()
                    )
                    await interaction.response.send_message(embed=embed)
                    return

                embed = discord.Embed(
                    title="📋 Очередь воспроизведения",
                    color=discord.Color.blue()
                )

                if queue_data.get("current_track"):
                    current = queue_data["current_track"]
                    embed.add_field(
                        name="🎵 Сейчас играет",
                        value=self.discord_client.format_track_info(
                            current.get("title", "Неизвестно"),
                            current.get("artist"),
                            current.get("duration")
                        ),
                        inline=False
                    )

                queue_text = ""
                max_tracks = 10

                for i, track in enumerate(tracks[:max_tracks], 1):
                    title = track.get("title", "Неизвестно")
                    duration = track.get("duration", 0)
                    requester = track.get("requester", "Неизвестно")
                    duration_str = f" `{self.discord_client.format_duration(duration)}`" if duration else ""
                    queue_text += f"`{i}.` **{title}**{duration_str} - <@{requester}>\n"

                if len(tracks) > max_tracks:
                    queue_text += f"\n... и ещё {len(tracks) - max_tracks} треков"

                if queue_text:
                    embed.add_field(
                        name=f"Следующие ({len(tracks)})",
                        value=queue_text,
                        inline=False
                    )

                total_duration = sum(track.get("duration", 0) for track in tracks)
                embed.set_footer(text=f"Общая длительность: {self.discord_client.format_duration(total_duration)}")
                await interaction.response.send_message(embed=embed)
            else:
                await self.discord_client.send_error_message(
                    interaction,
                    "Не удалось получить информацию об очереди."
                )

        except Exception as e:
            logger.error(f"Ошибка в команде queue: {e}")
            await self.discord_client.send_error_message(
                interaction,
                "Произошла ошибка при получении очереди."
            )

    @app_commands.command(name="skip", description="Пропустить текущий трек")
    async def skip(self, interaction: discord.Interaction):
        """Пропуск текущего трека"""
        try:
            response = await self._send_command(
                "skip",
                str(interaction.user.id),
                str(interaction.guild.id)
            )

            if response and response.get("status") == "accepted":
                await self.discord_client.send_success_message(interaction, "⏭️ Трек пропущен")
            else:
                await self.discord_client.send_error_message(interaction, "Не удалось пропустить трек.")
        except Exception as e:
            logger.error(f"Ошибка в команде skip: {e}")
            await self.discord_client.send_error_message(interaction, "Произошла ошибка при пропуске трека.")

    @app_commands.command(name="clear", description="Очистить очередь воспроизведения")
    async def clear(self, interaction: discord.Interaction):
        """Очистка очереди"""
        try:
            response = await self._send_command(
                "clear_queue",
                str(interaction.user.id),
                str(interaction.guild.id)
            )

            if response and response.get("status") == "accepted":
                await self.discord_client.send_success_message(interaction, "🗑️ Очередь очищена")
            else:
                await self.discord_client.send_error_message(interaction, "Не удалось очистить очередь.")
        except Exception as e:
            logger.error(f"Ошибка в команде clear: {e}")
            await self.discord_client.send_error_message(interaction, "Произошла ошибка при очистке очереди.")

    @app_commands.command(name="shuffle", description="Перемешать очередь воспроизведения")
    async def shuffle(self, interaction: discord.Interaction):
        """Перемешивание очереди"""
        try:
            response = await self._send_command(
                "shuffle",
                str(interaction.user.id),
                str(interaction.guild.id)
            )

            if response and response.get("status") == "accepted":
                await self.discord_client.send_success_message(interaction, "🔀 Очередь перемешана")
            else:
                await self.discord_client.send_error_message(interaction, "Не удалось перемешать очередь.")
        except Exception as e:
            logger.error(f"Ошибка в команде shuffle: {e}")
            await self.discord_client.send_error_message(interaction, "Произошла ошибка при перемешивании очереди.")

    @app_commands.command(name="remove", description="Удалить трек из очереди по номеру")
    @app_commands.describe(position="Номер трека в очереди (начиная с 1)")
    async def remove(self, interaction: discord.Interaction, position: int):
        """Удаление трека из очереди"""
        if position < 1:
            await self.discord_client.send_error_message(interaction, "Номер трека должен быть больше 0!")
            return

        try:
            response = await self._send_command(
                "remove",
                str(interaction.user.id),
                str(interaction.guild.id),
                position=position - 1
            )

            if response and response.get("status") == "accepted":
                removed_track = response.get("removed_track", {})
                title = removed_track.get("title", "Неизвестный трек")
                await self.discord_client.send_success_message(interaction, f"🗑️ Удален трек: **{title}**")
            else:
                await self.discord_client.send_error_message(interaction, "Не удалось удалить трек. Проверьте номер.")
        except Exception as e:
            logger.error(f"Ошибка в команде remove: {e}")
            await self.discord_client.send_error_message(interaction, "Произошла ошибка при удалении трека.")

    @app_commands.command(name="move", description="Переместить трек в очереди")
    @app_commands.describe(from_pos="Текущая позиция трека", to_pos="Новая позиция трека")
    async def move(self, interaction: discord.Interaction, from_pos: int, to_pos: int):
        """Перемещение трека в очереди"""
        if from_pos < 1 or to_pos < 1:
            await self.discord_client.send_error_message(interaction, "Позиции должны быть больше 0!")
            return

        if from_pos == to_pos:
            await self.discord_client.send_error_message(interaction, "Позиции не могут быть одинаковыми!")
            return

        try:
            response = await self._send_command(
                "move",
                str(interaction.user.id),
                str(interaction.guild.id),
                from_position=from_pos - 1,
                to_position=to_pos - 1
            )

            if response and response.get("status") == "accepted":
                moved_track = response.get("moved_track", {})
                title = moved_track.get("title", "Неизвестный трек")
                await self.discord_client.send_success_message(
                    interaction,
                    f"↕️ Трек **{title}** перемещен с позиции {from_pos} на {to_pos}"
                )
            else:
                await self.discord_client.send_error_message(interaction, "Не удалось переместить трек. Проверьте позиции.")
        except Exception as e:
            logger.error(f"Ошибка в команде move: {e}")
            await self.discord_client.send_error_message(interaction, "Произошла ошибка при перемещении трека.")

    @app_commands.command(name="loop", description="Управление зацикливанием")
    @app_commands.describe(mode="Режим зацикливания")
    @app_commands.choices(mode=[
        app_commands.Choice(name="Выключить", value="off"),
        app_commands.Choice(name="Зациклить трек", value="track"),
        app_commands.Choice(name="Зациклить очередь", value="queue")
    ])
    async def loop(self, interaction: discord.Interaction, mode: str):
        """Управление зацикливанием"""
        try:
            response = await self._send_command(
                "loop",
                str(interaction.user.id),
                str(interaction.guild.id),
                mode=mode
            )

            if response and response.get("status") == "accepted":
                mode_names = {"off": "выключено", "track": "зацикливание трека", "queue": "зацикливание очереди"}
                await self.discord_client.send_success_message(
                    interaction,
                    f"🔁 Зацикливание: **{mode_names.get(mode, mode)}**"
                )
            else:
                await self.discord_client.send_error_message(interaction, "Не удалось изменить режим зацикливания.")
        except Exception as e:
            logger.error(f"Ошибка в команде loop: {e}")
            await self.discord_client.send_error_message(interaction, "Произошла ошибка при изменении режима зацикливания.")

async def setup(bot):
    """Регистрация кога"""
    await bot.add_cog(QueueCommands(bot))