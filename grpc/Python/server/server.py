import grpc
from concurrent import futures
import asyncio
import logging
import sys
import os
import signal
import time
import json

# Добавляем путь к сгенерированному коду
from GRPC.Python.generated.v1 import discord_pb2
from GRPC.Python.generated.v1 import discord_pb2_grpc

# Добавляем модули для пула и метрик
from .metrics import record_request, get_metrics_collector, MetricsExporter

logger = logging.getLogger(__name__)


class CriticalErrorHandler:
    """Обработчик критических ошибок"""

    def __init__(self, bot):
        self.bot = bot
        self.last_error_time = 0
        self.error_count = 0
        self.error_window = 60  # секунд

    def handle(self, error: Exception, context: dict = None):
        """Обработка критической ошибки"""
        now = time.time()
        context = context or {}

        # Сброс счётчика если прошло больше окна
        if now - self.last_error_time > self.error_window:
            self.error_count = 0

        self.last_error_time = now
        self.error_count += 1

        error_str = str(error)
        logger.critical(f"💥 КРИТИЧЕСКАЯ ОШИБКА: {error_str}")
        logger.critical(f"Контекст: {context}")

        # Действия в зависимости от типа ошибки
        if isinstance(error, MemoryError):
            self._handle_memory_error(error, context)
        elif isinstance(error, ConnectionError) or "connection" in error_str.lower():
            self._handle_connection_error(error, context)
        elif "timeout" in error_str.lower():
            self._handle_timeout_error(error, context)
        elif "grpc" in error_str.lower() and "unavailable" in error_str.lower():
            self._handle_grpc_unavailable(error, context)
        elif self.error_count > 5:
            self._handle_error_storm(error, context)
        else:
            self._handle_general_error(error, context)

    def _handle_memory_error(self, error: Exception, context: dict):
        """Обработка ошибки памяти"""
        logger.critical("⚠️ ОШИБКА ПАМЯТИ! Попытка освободить ресурсы...")

        # Записываем состояние перед очисткой
        self._dump_state(context)

        # Очищаем кэш бота
        if hasattr(self.bot, 'discord_client'):
            if hasattr(self.bot.discord_client, 'command_cooldowns'):
                self.bot.discord_client.command_cooldowns.clear()
            if hasattr(self.bot.discord_client, 'user_permissions'):
                self.bot.discord_client.user_permissions.clear()

        # Очищаем кэш voice_manager
        if hasattr(self.bot, 'discord_client') and hasattr(self.bot.discord_client, 'voice_manager'):
            self.bot.discord_client.voice_manager.connections.clear()
            self.bot.discord_client.voice_manager.current_channels.clear()

        # Принудительная сборка мусора
        import gc
        gc.collect()

        logger.info("🧹 Ресурсы очищены")

    def _handle_connection_error(self, error: Exception, context: dict):
        """Обработка ошибки соединения"""
        logger.warning(f"🔌 Ошибка соединения: {error}")

        # Пытаемся переподключиться
        if hasattr(self.bot, 'reconnect_services'):
            try:
                self.bot.reconnect_services()
            except Exception as e:
                logger.error(f"Ошибка переподключения: {e}")

    def _handle_timeout_error(self, error: Exception, context: dict):
        """Обработка таймаута"""
        logger.warning(f"⏱️ Таймаут: {error}")

        # Увеличиваем таймаут для следующих запросов
        if hasattr(self.bot, 'increase_timeout'):
            self.bot.increase_timeout()

    def _handle_grpc_unavailable(self, error: Exception, context: dict):
        """Обработка недоступности gRPC"""
        logger.warning(f"📡 gRPC сервер недоступен: {error}")

        # Пытаемся перезапустить gRPC сервер
        if hasattr(self.bot, 'grpc_server') and self.bot.grpc_server:
            try:
                self.bot.grpc_server.stop()
                time.sleep(2)
                self.bot.grpc_server.start()
                logger.info("✅ gRPC сервер перезапущен")
            except Exception as e:
                logger.error(f"Ошибка перезапуска gRPC: {e}")

    def _handle_error_storm(self, error: Exception, context: dict):
        """Обработка шквала ошибок"""
        logger.critical(f"🌪️ ШКВАЛ ОШИБОК ({self.error_count} за {self.error_window} сек)")

        # Сохраняем дамп состояния
        self._dump_state(context)

        # Уведомляем администратора (если есть)
        self._notify_admin(error, context)

        # Если ошибок слишком много, перезапускаем бота
        if self.error_count > 10:
            logger.critical("⚠️ СЛИШКОМ МНОГО ОШИБОК! Перезапуск бота...")
            self._restart_bot()

    def _handle_general_error(self, error: Exception, context: dict):
        """Обработка общей ошибки"""
        logger.error(f"❌ Общая ошибка: {error}")

        # Логируем в файл
        self._log_to_file(error, context)

    def _dump_state(self, context: dict):
        """Сохранить дамп состояния"""
        try:
            state = {
                'timestamp': time.time(),
                'error': context,
                'metrics': get_metrics_collector().get_stats() if get_metrics_collector() else {},
                'connections': len(self.bot.discord_client.voice_manager.connections) if hasattr(self.bot, 'discord_client') and hasattr(self.bot.discord_client, 'voice_manager') else 0
            }

            with open('/tmp/openclaw_crash_dump.json', 'w') as f:
                json.dump(state, f, indent=2)

            logger.info("📄 Дамп состояния сохранён в /tmp/openclaw_crash_dump.json")
        except Exception as e:
            logger.error(f"Ошибка сохранения дампа: {e}")

    def _log_to_file(self, error: Exception, context: dict):
        """Записать ошибку в файл"""
        try:
            with open('/tmp/openclaw_errors.log', 'a') as f:
                f.write(f"[{time.time()}] {error}\n")
                f.write(f"Context: {context}\n\n")
        except Exception:
            pass

    def _notify_admin(self, error: Exception, context: dict):
        """Уведомить администратора"""
        # Отправляем в Discord (если есть)
        if hasattr(self.bot, 'send_admin_notification'):
            try:
                self.bot.send_admin_notification(
                    title="Критическая ошибка",
                    message=str(error),
                    details=context
                )
            except Exception:
                pass

    def _restart_bot(self):
        """Перезапустить бота"""
        try:
            # Сохраняем текущее состояние
            self._dump_state({})

            # Отключаемся от голосовых каналов
            if hasattr(self.bot, 'discord_client') and hasattr(self.bot.discord_client, 'voice_manager'):
                for guild_id in list(self.bot.discord_client.voice_manager.connections.keys()):
                    asyncio.run_coroutine_threadsafe(
                        self.bot.discord_client.voice_manager.disconnect_from_guild(guild_id),
                        self.bot.loop
                    )

            # Останавливаем gRPC сервер
            if hasattr(self.bot, 'grpc_server') and self.bot.grpc_server:
                self.bot.grpc_server.stop()

            # Перезапускаем процесс
            logger.info("🔄 Перезапуск бота...")
            python = sys.executable
            os.execl(python, python, *sys.argv)

        except Exception as e:
            logger.critical(f"❌ Ошибка при перезапуске: {e}")
            # Принудительный выход
            os._exit(1)


class DiscordServicer(discord_pb2_grpc.DiscordServiceServicer):
    def __init__(self, bot):
        self.bot = bot
        self.metrics = get_metrics_collector()
        self.error_handler = CriticalErrorHandler(bot)

    def SendCommand(self, request, context):
        """Обработка команды от Java Gateway"""
        start_time = time.time()
        method = 'SendCommand'
        
        try:
            logger.info(f"📥 gRPC команда: {request.command} от {request.user_id}")
            
            # Отправляем команду в основной бот (асинхронно)
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
            
            duration_ms = (time.time() - start_time) * 1000
            record_request(method, duration_ms, success=True)
            
            return discord_pb2.CommandResponse(
                success=True,
                message="Command accepted",
                data={"status": "accepted"}
            )
            
        except MemoryError as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request(method, duration_ms, success=False, error=str(e))
            logger.error(f"Ошибка памяти в SendCommand: {e}")
            self.error_handler.handle(e, {'method': method, 'request': request})
            return discord_pb2.CommandResponse(
                success=False,
                message=f"Memory error: {str(e)}",
                data={"error": "memory_error"}
            )
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request(method, duration_ms, success=False, error=str(e))
            logger.error(f"Ошибка в SendCommand: {e}")
            
            # Обрабатываем критическую ошибку
            if self._is_critical_error(e):
                self.error_handler.handle(e, {'method': method, 'request': request})
            
            return discord_pb2.CommandResponse(
                success=False,
                message=f"Error: {str(e)}",
                data={"error": str(e)}
            )

    def _is_critical_error(self, error: Exception) -> bool:
        """Определить, является ли ошибка критической"""
        error_str = str(error).lower()
        critical_patterns = [
            'memory', 'connection', 'timeout', 'unavailable',
            'grpc', 'database', 'crash', 'fatal'
        ]
        return any(pattern in error_str for pattern in critical_patterns)

    def GetStatus(self, request, context):
        """Получение статуса"""
        start_time = time.time()
        method = 'GetStatus'
        
        try:
            guild_id = request.guild_id
            status = self.bot.discord_client.voice_manager.get_connection(int(guild_id)) if guild_id else None
            
            duration_ms = (time.time() - start_time) * 1000
            record_request(method, duration_ms, success=True)
            
            return discord_pb2.StatusResponse(
                playing=status is not None and status.is_playing(),
                current_track="",
                volume=50,
                queue_length=0
            )
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request(method, duration_ms, success=False, error=str(e))
            logger.error(f"Ошибка в GetStatus: {e}")
            
            if self._is_critical_error(e):
                self.error_handler.handle(e, {'method': method, 'request': request})
            
            return discord_pb2.StatusResponse(
                playing=False,
                current_track="",
                volume=50,
                queue_length=0
            )

class GrpcServer:
    """gRPC сервер с поддержкой пула, метрик и обработкой критических ошибок"""
    
    def __init__(self, bot, host='0.0.0.0', port=50051, max_workers=10, use_pool=False):
        self.bot = bot
        self.host = host
        self.port = port
        self.max_workers = max_workers
        self.use_pool = use_pool
        self.server = None
        self.metrics = get_metrics_collector()
        self.metrics_exporter = MetricsExporter(self.metrics)
        self._running = False
        self.error_handler = CriticalErrorHandler(bot)
        
        # Настройка сигналов для graceful shutdown
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def _signal_handler(self, sig, frame):
        """Обработка сигналов для graceful shutdown"""
        logger.info(f"Получен сигнал {sig}, останавливаем сервер...")
        self.stop()
    
    def start(self):
        """Запуск gRPC сервера"""
        try:
            self.server = grpc.server(
                futures.ThreadPoolExecutor(max_workers=self.max_workers),
                options=[
                    ('grpc.max_send_message_length', 100 * 1024 * 1024),
                    ('grpc.max_receive_message_length', 100 * 1024 * 1024),
                    ('grpc.keepalive_time_ms', 30000),
                    ('grpc.keepalive_timeout_ms', 10000),
                ]
            )
            
            discord_pb2_grpc.add_DiscordServiceServicer_to_server(
                DiscordServicer(self.bot), self.server
            )
            
            self.server.add_insecure_port(f'{self.host}:{self.port}')
            self.server.start()
            self._running = True
            
            logger.info(f"🚀 gRPC сервер запущен на {self.host}:{self.port}")
            logger.info(f"   max_workers: {self.max_workers}")
            
            # Запускаем фоновую задачу для периодического логирования метрик
            asyncio.create_task(self._log_metrics_periodically())
            
            return self.server
            
        except Exception as e:
            logger.critical(f"❌ Ошибка запуска gRPC сервера: {e}")
            self.error_handler.handle(e, {'action': 'start_server'})
            raise
    
    def stop(self, grace=5):
        """Остановка gRPC сервера"""
        if not self._running:
            return
        
        logger.info("🛑 Остановка gRPC сервера...")
        self._running = False
        
        try:
            if self.server:
                self.server.stop(grace)
                logger.info(f"✅ gRPC сервер остановлен (grace={grace}s)")
        except Exception as e:
            logger.error(f"Ошибка при остановке сервера: {e}")
    
    def wait_for_termination(self):
        """Ожидание завершения сервера"""
        if self.server:
            self.server.wait_for_termination()
    
    async def _log_metrics_periodically(self, interval=60):
        """Периодическое логирование метрик"""
        while self._running:
            await asyncio.sleep(interval)
            try:
                stats = self.metrics_exporter.to_text()
                logger.info(f"\n📊 gRPC Metrics:\n{stats}")
            except Exception as e:
                logger.error(f"Ошибка логирования метрик: {e}")
    
    def get_metrics(self, format='text'):
        """Получить метрики в указанном формате"""
        try:
            if format == 'prometheus':
                return self.metrics_exporter.to_prometheus()
            elif format == 'json':
                return self.metrics_exporter.to_json()
            else:
                return self.metrics_exporter.to_text()
        except Exception as e:
            logger.error(f"Ошибка получения метрик: {e}")
            return f"Error: {e}"
    
    def get_stats(self):
        """Получить статистику сервера"""
        try:
            return {
                'status': 'running' if self._running else 'stopped',
                'host': self.host,
                'port': self.port,
                'max_workers': self.max_workers,
                'use_pool': self.use_pool,
                'metrics': self.metrics.get_stats()
            }
        except Exception as e:
            logger.error(f"Ошибка получения статистики: {e}")
            return {'status': 'error', 'error': str(e)}


def start_grpc_server(bot, host='0.0.0.0', port=50051, max_workers=10, use_pool=False):
    """Удобная функция запуска сервера"""
    server = GrpcServer(bot, host, port, max_workers, use_pool)
    server.start()
    return server