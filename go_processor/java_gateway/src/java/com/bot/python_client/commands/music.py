"""
Music Commands Cog
Команды для управления музыкой в Discord боте
"""

import discord
from discord import app_commands
from discord.ext import commands
import logging
import grpc
import os
import sys

# Добавляем путь к gRPC модулям
sys.path.insert(0, '/mnt/c/Мои проекты/Kodland/elixir_music_bot')
sys.path.insert(0, '/mnt/c/Мои проекты/Kodland/elixir_music_bot/GRPC/Python')
from GRPC.Python.generated.v1 import discord_pb2_grpc as v1_discord_pb2_grpc
from GRPC.Python.generated.v1 import discord_pb2 as v1_discord_pb2

logger = logging.getLogger(__name__)

class MusicCommands(commands.Cog):
    """Ког для музыкальных команд"""

    def __init__(self, bot):
        self.bot = bot
        self.discord_client = bot.discord_client
        self.use_grpc = os.getenv('USE_GRPC', 'false').lower() == 'true'
        self.grpc_channel = None
        self.grpc_stub = None
        
        if self.use_grpc:
            try:
                self.grpc_channel = grpc.insecure_channel('localhost:50051')
                self.grpc_stub = v1_discord_pb2_grpc.DiscordServiceStub(self.grpc_channel)
                logger.info("✅ gRPC клиент инициализирован")
            except Exception as e:
                logger.error(f"❌ Ошибка инициализации gRPC: {e}")
                self.use_grpc = False

    async def _send_command(self, command: str, user_id: str, guild_id: str, **kwargs):
        """Отправка команды через HTTP или gRPC"""
        if self.use_grpc and self.grpc_stub:
            try:
                request = v1_discord_pb2.CommandRequest(
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

    @app_commands.command(name="play", description="Воспроизвести музыку по URL или названию")
    @app_commands.describe(url="URL видео YouTube или название трека")
    async def play(self, interaction: discord.Interaction, url: str):
        """Команда воспроизведения музыки"""
        await interaction.response.defer()

        # Проверяем кулдаун
        if not self.discord_client.check_cooldown("play", interaction.user.id, 3.0):
            await self.discord_client.send_error_message(
                interaction,
                "Подождите немного перед следующим использованием команды!"
            )
            return

        # Обеспечиваем голосовое подключение
        if not await self.discord_client.ensure_voice_connection(interaction):
            return

        try:
            response = await self._send_command(
                "play",
                str(interaction.user.id),
                str(interaction.guild.id),
                url=url,
                channel_id=str(interaction.channel.id)
            )

            if response and response.get("status") == "accepted":
                embed = discord.Embed(
                    title="🎵 Добавление в очередь",
                    description=f"Обработка: **{url}**",
                    color=discord.Color.blue()
                )
                await interaction.followup.send(embed=embed)
            else:
                await self.discord_client.send_error_message(
                    interaction,
                    "Не удалось обработать запрос. Попробуйте позже."
                )

        except Exception as e:
            logger.error(f"Ошибка в команде play: {e}")
            await self.discord_client.send_error_message(
                interaction,
                "Произошла ошибка при обработке команды."
            )

    @app_commands.command(name="pause", description="Приостановить воспроизведение")
    async def pause(self, interaction: discord.Interaction):
        """Приостановка воспроизведения"""
        vc = self.discord_client.voice_manager.get_connection(interaction.guild.id)
        if not vc or not vc.is_playing():
            await self.discord_client.send_error_message(
                interaction,
                "Сейчас ничего не воспроизводится!"
            )
            return

        vc.pause()
        await self.discord_client.send_success_message(
            interaction,
            "⏸️ Воспроизведение приостановлено"
        )

    @app_commands.command(name="resume", description="Возобновить воспроизведение")
    async def resume(self, interaction: discord.Interaction):
        """Возобновление воспроизведения"""
        vc = self.discord_client.voice_manager.get_connection(interaction.guild.id)
        if not vc or not vc.is_paused():
            await self.discord_client.send_error_message(
                interaction,
                "Воспроизведение не приостановлено!"
            )
            return

        vc.resume()
        await self.discord_client.send_success_message(
            interaction,
            "▶️ Воспроизведение возобновлено"
        )

    @app_commands.command(name="stop", description="Остановить воспроизведение и очистить очередь")
    async def stop(self, interaction: discord.Interaction):
        """Остановка воспроизведения"""
        vc = self.discord_client.voice_manager.get_connection(interaction.guild.id)
        if not vc:
            await self.discord_client.send_error_message(
                interaction,
                "Бот не подключен к голосовому каналу!"
            )
            return

        vc.stop()
        await self.discord_client.voice_manager.disconnect_from_guild(interaction.guild.id)

        await self.discord_client.send_success_message(
            interaction,
            "⏹️ Воспроизведение остановлено и очередь очищена"
        )

    @app_commands.command(name="volume", description="Изменить громкость (0-100)")
    @app_commands.describe(level="Уровень громкости (0-100)")
    async def volume(self, interaction: discord.Interaction, level: int):
        """Изменение громкости"""
        if not 0 <= level <= 100:
            await self.discord_client.send_error_message(
                interaction,
                "Уровень громкости должен быть от 0 до 100!"
            )
            return

        try:
            response = await self._send_command(
                "volume",
                str(interaction.user.id),
                str(interaction.guild.id),
                level=level / 100.0
            )

            if response and response.get("status") == "accepted":
                await self.discord_client.send_success_message(
                    interaction,
                    f"🔊 Громкость установлена на {level}%"
                )
            else:
                await self.discord_client.send_error_message(
                    interaction,
                    "Не удалось изменить громкость."
                )

        except Exception as e:
            logger.error(f"Ошибка в команде volume: {e}")
            await self.discord_client.send_error_message(
                interaction,
                "Произошла ошибка при изменении громкости."
            )

    @app_commands.command(name="nowplaying", description="Показать текущий трек")
    async def nowplaying(self, interaction: discord.Interaction):
        """Показать информацию о текущем треке"""
        try:
            response = await self._send_command(
                "status",
                str(interaction.user.id),
                str(interaction.guild.id)
            )

            if response and response.get("current_track"):
                track = response["current_track"]
                embed = discord.Embed(
                    title="🎵 Сейчас играет",
                    color=discord.Color.blue()
                )

                embed.add_field(
                    name="Трек",
                    value=self.discord_client.format_track_info(
                        track.get("title", "Неизвестно"),
                        track.get("artist"),
                        track.get("duration")
                    ),
                    inline=False
                )

                if track.get("requester"):
                    embed.add_field(
                        name="Заказал",
                        value=f"<@{track['requester']}>",
                        inline=True
                    )

                if track.get("position") and track.get("duration"):
                    progress = track["position"] / track["duration"]
                    bar_length = 20
                    filled = int(bar_length * progress)
                    bar = "█" * filled + "░" * (bar_length - filled)

                    embed.add_field(
                        name="Прогресс",
                        value=f"{bar} {self.discord_client.format_duration(track['position'])}/{self.discord_client.format_duration(track['duration'])}",
                        inline=False
                    )

                await interaction.response.send_message(embed=embed)
            else:
                await self.discord_client.send_error_message(
                    interaction,
                    "Сейчас ничего не воспроизводится."
                )

        except Exception as e:
            logger.error(f"Ошибка в команде nowplaying: {e}")
            await self.discord_client.send_error_message(
                interaction,
                "Произошла ошибка при получении информации о треке."
            )

    @app_commands.command(name="effects", description="Применить аудио эффекты")
    @app_commands.describe(
        effect="Тип эффекта",
        intensity="Интенсивность эффекта (0.0-1.0)"
    )
    @app_commands.choices(effect=[
        app_commands.Choice(name="Эхо", value="echo"),
        app_commands.Choice(name="Реверберация", value="reverb"),
        app_commands.Choice(name="Дисторшн", value="distortion"),
        app_commands.Choice(name="Хорус", value="chorus"),
        app_commands.Choice(name="Флэнджер", value="flanger"),
        app_commands.Choice(name="Фэйзер", value="phaser"),
        app_commands.Choice(name="Эквалайзер", value="equalizer")
    ])
    async def effects(self, interaction: discord.Interaction, effect: str, intensity: float = 0.5):
        """Применение аудио эффектов"""
        if not 0.0 <= intensity <= 1.0:
            await self.discord_client.send_error_message(
                interaction,
                "Интенсивность должна быть от 0.0 до 1.0!"
            )
            return

        try:
            response = await self._send_command(
                "effects",
                str(interaction.user.id),
                str(interaction.guild.id),
                effect_type=effect,
                intensity=intensity
            )

            if response and response.get("status") == "accepted":
                effect_names = {
                    "echo": "Эхо",
                    "reverb": "Реверберация",
                    "distortion": "Дисторшн",
                    "chorus": "Хорус",
                    "flanger": "Флэнджер",
                    "phaser": "Фэйзер",
                    "equalizer": "Эквалайзер"
                }

                await self.discord_client.send_success_message(
                    interaction,
                    f"🎚️ Эффект **{effect_names.get(effect, effect)}** применен с интенсивностью {intensity:.1f}"
                )
            else:
                await self.discord_client.send_error_message(
                    interaction,
                    "Не удалось применить эффект."
                )

        except Exception as e:
            logger.error(f"Ошибка в команде effects: {e}")
            await self.discord_client.send_error_message(
                interaction,
                "Произошла ошибка при применении эффекта."
            )

async def setup(bot):
    """Регистрация кога"""
    await bot.add_cog(MusicCommands(bot))