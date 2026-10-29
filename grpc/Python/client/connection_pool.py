#!/usr/bin/env python3
"""
Пул gRPC соединений для клиента
"""

import grpc
import logging
import time
from typing import Optional, Dict
from dataclasses import dataclass
from datetime import datetime

from GRPC.Python.generated.v1 import discord_pb2_grpc

# Добавляем метрики
from client.metrics import record_connection_event, get_metrics_collector

logger = logging.getLogger(__name__)


@dataclass
class ClientConnection:
    """Информация о клиентском соединении"""
    channel: grpc.Channel
    stub: any
    created_at: datetime
    last_used: datetime
    active: bool = True
    requests_count: int = 0
    errors_count: int = 0
    total_duration_ms: float = 0.0


class ClientConnectionPool:
    """Пул gRPC соединений для клиента"""

    def __init__(self, host='localhost', port=50051, max_connections=5, idle_timeout=300):
        self.host = host
        self.port = port
        self.max_connections = max_connections
        self.idle_timeout = idle_timeout
        self.connections: Dict[str, ClientConnection] = {}
        self._lock = False
        self.metrics = get_metrics_collector()

    def _get_key(self, host: str = None, port: int = None) -> str:
        return f"{host or self.host}:{port or self.port}"

    def _create_connection(self, host: str = None, port: int = None) -> ClientConnection:
        """Создать новое соединение"""
        start_time = time.time()
        host = host or self.host
        port = port or self.port
        key = self._get_key(host, port)

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

            conn = ClientConnection(
                channel=channel,
                stub=stub,
                created_at=datetime.now(),
                last_used=datetime.now()
            )

            self.connections[key] = conn
            
            duration_ms = (time.time() - start_time) * 1000
            record_connection_event('create', key, duration_ms, success=True)
            logger.debug(f"Создано клиентское gRPC соединение {key}")

            return conn
            
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_connection_event('create', key, duration_ms, success=False)
            logger.error(f"Ошибка создания соединения {key}: {e}")
            raise

    def get_connection(self, host: str = None, port: int = None) -> Optional[ClientConnection]:
        """Получить соединение из пула"""
        start_time = time.time()
        key = self._get_key(host, port)

        conn = self.connections.get(key)

        if conn and conn.active:
            conn.last_used = datetime.now()
            conn.requests_count += 1
            duration_ms = (time.time() - start_time) * 1000
            record_connection_event('get', key, duration_ms, success=True)
            return conn

        if len(self.connections) < self.max_connections:
            conn = self._create_connection(host, port)
            conn.requests_count += 1
            duration_ms = (time.time() - start_time) * 1000
            record_connection_event('get', key, duration_ms, success=True)
            return conn

        # Ищем неактивное или самое старое
        for k, c in self.connections.items():
            if not c.active:
                self._close_connection(k)
                conn = self._create_connection(host, port)
                conn.requests_count += 1
                duration_ms = (time.time() - start_time) * 1000
                record_connection_event('get', key, duration_ms, success=True)
                return conn

        oldest = min(self.connections.items(), key=lambda x: x[1].last_used)
        self._close_connection(oldest[0])
        conn = self._create_connection(host, port)
        conn.requests_count += 1
        duration_ms = (time.time() - start_time) * 1000
        record_connection_event('get', key, duration_ms, success=True)
        return conn

    def _close_connection(self, key: str):
        """Закрыть соединение"""
        start_time = time.time()
        conn = self.connections.get(key)
        if conn:
            try:
                conn.active = False
                conn.channel.close()
                del self.connections[key]
                duration_ms = (time.time() - start_time) * 1000
                record_connection_event('close', key, duration_ms, success=True)
                logger.debug(f"Закрыто клиентское gRPC соединение {key}")
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                record_connection_event('close', key, duration_ms, success=False)
                logger.warning(f"Ошибка закрытия соединения {key}: {e}")

    def record_request_result(self, conn: ClientConnection, success: bool = True, error: str = None, duration_ms: float = 0):
        """Записать результат запроса через это соединение"""
        if not success:
            conn.errors_count += 1
        if duration_ms > 0:
            conn.total_duration_ms += duration_ms
        record_connection_event('request', conn.created_at.isoformat(), duration_ms, success)

    def record_error(self, conn: ClientConnection):
        """Записать ошибку для соединения"""
        conn.errors_count += 1
        record_connection_event('error', conn.created_at.isoformat(), 0, success=False)

    def close_all(self):
        """Закрыть все соединения"""
        for key in list(self.connections.keys()):
            self._close_connection(key)
        logger.info("Все клиентские gRPC соединения закрыты")

    def get_stats(self) -> dict:
        """Получить статистику пула"""
        return {
            'total_connections': len(self.connections),
            'max_connections': self.max_connections,
            'idle_timeout': self.idle_timeout,
            'connections': [
                {
                    'key': key,
                    'requests': conn.requests_count,
                    'errors': conn.errors_count,
                    'success_rate': (conn.requests_count - conn.errors_count) / conn.requests_count if conn.requests_count > 0 else 0,
                    'avg_response_time_ms': conn.total_duration_ms / conn.requests_count if conn.requests_count > 0 else 0,
                    'created_at': conn.created_at.isoformat(),
                    'last_used': conn.last_used.isoformat(),
                    'idle_seconds': (datetime.now() - conn.last_used).total_seconds(),
                    'active': conn.active
                }
                for key, conn in self.connections.items()
            ]
        }

    def get_load(self) -> float:
        """Получить текущую загрузку пула"""
        if self.max_connections == 0:
            return 0.0
        return len(self.connections) / self.max_connections


# Глобальный пул
_default_pool = None


def get_client_pool(host='localhost', port=50051, max_connections=5, idle_timeout=300) -> ClientConnectionPool:
    """Получить глобальный пул клиентских соединений"""
    global _default_pool
    if _default_pool is None:
        _default_pool = ClientConnectionPool(host, port, max_connections, idle_timeout)
    return _default_pool


def close_client_pool():
    """Закрыть глобальный пул"""
    global _default_pool
    if _default_pool:
        _default_pool.close_all()
        _default_pool = None