#!/usr/bin/env python3
"""
Пул клиентских gRPC соединений для отправки команд в Java Gateway
"""

import grpc
import logging
import time
from typing import Optional, Dict
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum

from GRPC.Python.generated.v1 import discord_pb2_grpc

# Добавляем метрики
from client.metrics import record_connection_event, get_metrics_collector

logger = logging.getLogger(__name__)


class ConnectionStatus(Enum):
    """Статус соединения"""
    IDLE = "idle"
    ACTIVE = "active"
    ERROR = "error"
    CLOSED = "closed"


@dataclass
class PoolConnection:
    """Информация о соединении в пуле"""
    id: int
    channel: grpc.Channel
    stub: any
    host: str
    port: int
    status: ConnectionStatus = ConnectionStatus.IDLE
    created_at: datetime = field(default_factory=datetime.now)
    last_used: datetime = field(default_factory=datetime.now)
    requests_sent: int = 0
    errors: int = 0
    total_time_ms: float = 0.0


class ClientConnectionPool:
    """
    Пул клиентских gRPC соединений
    
    Особенности:
    - Переиспользование соединений
    - Автоматическое восстановление при ошибках
    - Балансировка нагрузки
    - Мониторинг состояния
    """

    def __init__(self, 
                 host: str = 'localhost', 
                 port: int = 50051,
                 max_connections: int = 10,
                 min_connections: int = 2,
                 idle_timeout: int = 300,
                 health_check_interval: int = 60):
        self.host = host
        self.port = port
        self.max_connections = max_connections
        self.min_connections = min_connections
        self.idle_timeout = idle_timeout
        self.health_check_interval = health_check_interval
        self.metrics = get_metrics_collector()
        
        self.connections: Dict[int, PoolConnection] = {}
        self._next_id = 1
        self._lock = False
        self._running = True
        
        # Запускаем фоновую очистку
        self._start_cleanup_thread()
        
        # Создаём минимальное количество соединений
        for _ in range(min_connections):
            self._create_connection()

    def _create_connection(self, host: str = None, port: int = None) -> PoolConnection:
        """Создать новое соединение"""
        start_time = time.time()
        host = host or self.host
        port = port or self.port
        
        try:
            channel = grpc.insecure_channel(
                f'{host}:{port}',
                options=[
                    ('grpc.max_send_message_length', 100 * 1024 * 1024),
                    ('grpc.max_receive_message_length', 100 * 1024 * 1024),
                    ('grpc.keepalive_time_ms', 30000),
                    ('grpc.keepalive_timeout_ms', 10000),
                ]
            )
            stub = discord_pb2_grpc.DiscordServiceStub(channel)
            
            conn = PoolConnection(
                id=self._next_id,
                channel=channel,
                stub=stub,
                host=host,
                port=port
            )
            
            self._next_id += 1
            self.connections[conn.id] = conn
            
            duration_ms = (time.time() - start_time) * 1000
            record_connection_event('create', conn.id, duration_ms, success=True)
            logger.debug(f"✅ Создано соединение {conn.id} для {host}:{port}")
            return conn
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_connection_event('create', 0, duration_ms, success=False)
            logger.error(f"❌ Ошибка создания соединения: {e}")
            raise

    def _close_connection(self, conn_id: int):
        """Закрыть соединение"""
        start_time = time.time()
        conn = self.connections.get(conn_id)
        if conn:
            try:
                conn.status = ConnectionStatus.CLOSED
                conn.channel.close()
                del self.connections[conn_id]
                duration_ms = (time.time() - start_time) * 1000
                record_connection_event('close', conn_id, duration_ms, success=True)
                logger.debug(f"🔌 Закрыто соединение {conn_id}")
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                record_connection_event('close', conn_id, duration_ms, success=False)
                logger.warning(f"Ошибка при закрытии соединения {conn_id}: {e}")

    def _get_idle_connection(self) -> Optional[PoolConnection]:
        """Получить свободное соединение"""
        for conn in self.connections.values():
            if conn.status == ConnectionStatus.IDLE:
                conn.status = ConnectionStatus.ACTIVE
                conn.last_used = datetime.now()
                return conn
        return None

    def _get_least_used_connection(self) -> Optional[PoolConnection]:
        """Получить наименее нагруженное соединение"""
        active = [c for c in self.connections.values() if c.status == ConnectionStatus.ACTIVE]
        if active:
            return min(active, key=lambda c: c.requests_sent)
        return None

    def get_connection(self) -> Optional[PoolConnection]:
        """
        Получить соединение из пула
        
        Стратегия:
        1. Сначала ищем свободное
        2. Если нет, создаём новое (если не достигнут максимум)
        3. Если максимум достигнут, берём наименее нагруженное
        """
        start_time = time.time()
        
        # Ищем свободное
        conn = self._get_idle_connection()
        if conn:
            duration_ms = (time.time() - start_time) * 1000
            record_connection_event('get', conn.id, duration_ms, success=True)
            return conn
        
        # Создаём новое, если не достигнут лимит
        if len(self.connections) < self.max_connections:
            conn = self._create_connection()
            conn.status = ConnectionStatus.ACTIVE
            conn.last_used = datetime.now()
            duration_ms = (time.time() - start_time) * 1000
            record_connection_event('get', conn.id, duration_ms, success=True)
            return conn
        
        # Берём наименее нагруженное
        conn = self._get_least_used_connection()
        if conn:
            conn.last_used = datetime.now()
            duration_ms = (time.time() - start_time) * 1000
            record_connection_event('get', conn.id, duration_ms, success=True)
            return conn
        
        # Fallback — первое активное
        for c in self.connections.values():
            if c.status == ConnectionStatus.ACTIVE:
                c.last_used = datetime.now()
                duration_ms = (time.time() - start_time) * 1000
                record_connection_event('get', c.id, duration_ms, success=True)
                return c
        
        duration_ms = (time.time() - start_time) * 1000
        record_connection_event('get', 0, duration_ms, success=False)
        return None

    def release_connection(self, conn: PoolConnection, error: bool = False, duration_ms: float = 0):
        """Освободить соединение"""
        if error:
            conn.errors += 1
            conn.status = ConnectionStatus.ERROR
            
            record_connection_event('error', conn.id, duration_ms, success=False)
            
            # При ошибке закрываем и создаём новое
            conn_id = conn.id
            self._close_connection(conn_id)
            new_conn = self._create_connection()
            new_conn.requests_sent = conn.requests_sent
            new_conn.total_time_ms = conn.total_time_ms
            return new_conn
        else:
            conn.status = ConnectionStatus.IDLE
            conn.requests_sent += 1
            conn.total_time_ms += duration_ms
            record_connection_event('release', conn.id, duration_ms, success=True)

    def execute(self, func, *args, **kwargs):
        """
        Выполнить функцию с соединением из пула
        
        Автоматически получает и освобождает соединение
        """
        start_time = time.time()
        conn = self.get_connection()
        
        if not conn:
            raise Exception("No connection available")
        
        try:
            result = func(conn, *args, **kwargs)
            duration_ms = (time.time() - start_time) * 1000
            self.release_connection(conn, duration_ms=duration_ms)
            return result
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            self.release_connection(conn, error=True, duration_ms=duration_ms)
            raise

    def _start_cleanup_thread(self):
        """Запустить фоновую очистку неактивных соединений"""
        import threading
        
        def cleanup_worker():
            while self._running:
                time.sleep(self.health_check_interval)
                self._cleanup_idle_connections()
                self._health_check()
        
        thread = threading.Thread(target=cleanup_worker, daemon=True)
        thread.start()

    def _cleanup_idle_connections(self):
        """Очистка долго неиспользуемых соединений"""
        now = datetime.now()
        to_remove = []
        
        for conn_id, conn in self.connections.items():
            idle_seconds = (now - conn.last_used).total_seconds()
            if idle_seconds > self.idle_timeout and len(self.connections) > self.min_connections:
                to_remove.append(conn_id)
        
        for conn_id in to_remove:
            self._close_connection(conn_id)
            logger.debug(f"Очищено неактивное соединение {conn_id}")

    def _health_check(self):
        """Проверка здоровья соединений"""
        for conn_id, conn in list(self.connections.items()):
            try:
                state = conn.channel.get_state(try_to_connect=False)
                if state == grpc.ChannelConnectivity.SHUTDOWN:
                    self._close_connection(conn_id)
                    self._create_connection()
                    record_connection_event('health_check_failed', conn_id, 0, success=False)
            except Exception as e:
                logger.warning(f"Health check failed for connection {conn_id}: {e}")
                self._close_connection(conn_id)
                self._create_connection()
                record_connection_event('health_check_failed', conn_id, 0, success=False)

    def close_all(self):
        """Закрыть все соединения"""
        self._running = False
        for conn_id in list(self.connections.keys()):
            self._close_connection(conn_id)
        logger.info("Все клиентские gRPC соединения закрыты")

    def get_stats(self) -> dict:
        """Получить статистику пула"""
        return {
            'total_connections': len(self.connections),
            'max_connections': self.max_connections,
            'min_connections': self.min_connections,
            'idle_timeout': self.idle_timeout,
            'connections': [
                {
                    'id': conn.id,
                    'host': conn.host,
                    'port': conn.port,
                    'status': conn.status.value,
                    'requests_sent': conn.requests_sent,
                    'errors': conn.errors,
                    'error_rate': conn.errors / conn.requests_sent if conn.requests_sent > 0 else 0,
                    'avg_time_ms': conn.total_time_ms / conn.requests_sent if conn.requests_sent > 0 else 0,
                    'created_at': conn.created_at.isoformat(),
                    'last_used': conn.last_used.isoformat(),
                    'idle_seconds': (datetime.now() - conn.last_used).total_seconds()
                }
                for conn in self.connections.values()
            ]
        }

    def get_load(self) -> float:
        """Получить текущую загрузку пула"""
        if not self.connections:
            return 0.0
        active = sum(1 for c in self.connections.values() if c.status == ConnectionStatus.ACTIVE)
        return active / len(self.connections)


# Глобальный пул
_default_pool = None


def get_client_pool(host='localhost', port=50051, max_connections=10, min_connections=2) -> ClientConnectionPool:
    """Получить глобальный пул клиентских соединений"""
    global _default_pool
    if _default_pool is None:
        _default_pool = ClientConnectionPool(host, port, max_connections, min_connections)
    return _default_pool


def close_client_pool():
    """Закрыть глобальный пул"""
    global _default_pool
    if _default_pool:
        _default_pool.close_all()
        _default_pool = None