#!/usr/bin/env python3
"""
Пул gRPC соединений для управления несколькими каналами
"""

import grpc
import logging
import time
from typing import Optional, Dict
from dataclasses import dataclass
from datetime import datetime

from GRPC.Python.generated.v1 import discord_pb2_grpc

# Добавляем метрики
from server.metrics import record_request, get_metrics_collector

logger = logging.getLogger(__name__)

@dataclass
class Connection:
    """Информация о соединении"""
    channel: grpc.Channel
    stub: any
    created_at: datetime
    last_used: datetime
    active: bool = True
    total_requests: int = 0
    failed_requests: int = 0
    total_duration_ms: float = 0.0


class ConnectionPool:
    """Пул gRPC соединений"""

    def __init__(self, host='localhost', port=50051, max_connections=10, idle_timeout=300):
        self.host = host
        self.port = port
        self.max_connections = max_connections
        self.idle_timeout = idle_timeout  # секунд
        self.connections: Dict[str, Connection] = {}
        self._counter = 0
        self._metrics = get_metrics_collector()

    def _get_connection_key(self, host: str, port: int) -> str:
        return f"{host}:{port}"

    def _create_connection(self, host: str = None, port: int = None) -> Connection:
        """Создать новое соединение"""
        start_time = time.time()
        host = host or self.host
        port = port or self.port
        key = self._get_connection_key(host, port)

        try:
            channel = grpc.insecure_channel(f'{host}:{port}')
            stub = discord_pb2_grpc.DiscordServiceStub(channel)
            now = datetime.now()

            conn = Connection(
                channel=channel,
                stub=stub,
                created_at=now,
                last_used=now
            )

            self.connections[key] = conn
            duration_ms = (time.time() - start_time) * 1000
            record_request('connection_create', duration_ms, success=True)
            logger.debug(f"Создано gRPC соединение {key}")

            return conn

        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request('connection_create', duration_ms, success=False, error=str(e))
            raise

    def get_connection(self, host: str = None, port: int = None) -> Optional[Connection]:
        """Получить соединение из пула или создать новое"""
        start_time = time.time()
        host = host or self.host
        port = port or self.port
        key = self._get_connection_key(host, port)

        conn = self.connections.get(key)

        if conn and conn.active:
            conn.last_used = datetime.now()
            conn.total_requests += 1
            duration_ms = (time.time() - start_time) * 1000
            conn.total_duration_ms += duration_ms
            record_request('connection_get', duration_ms, success=True)
            return conn

        # Создаём новое, если не превышен лимит
        if len(self.connections) < self.max_connections:
            conn = self._create_connection(host, port)
            if conn:
                conn.total_requests += 1
                duration_ms = (time.time() - start_time) * 1000
                conn.total_duration_ms += duration_ms
                record_request('connection_get', duration_ms, success=True)
            return conn

        # Ищем неактивное или самое старое
        for k, c in self.connections.items():
            if not c.active:
                self._close_connection(k)
                conn = self._create_connection(host, port)
                if conn:
                    conn.total_requests += 1
                    duration_ms = (time.time() - start_time) * 1000
                    conn.total_duration_ms += duration_ms
                    record_request('connection_get', duration_ms, success=True)
                return conn

        # Все активны — берём самое старое
        oldest = min(self.connections.items(), key=lambda x: x[1].last_used)
        self._close_connection(oldest[0])
        conn = self._create_connection(host, port)
        if conn:
            conn.total_requests += 1
            duration_ms = (time.time() - start_time) * 1000
            conn.total_duration_ms += duration_ms
            record_request('connection_get', duration_ms, success=True)
        return conn

    def record_request_result(self, conn: Connection, success: bool = True, error: str = None, duration_ms: float = 0):
        """Записать результат запроса через это соединение"""
        if not success:
            conn.failed_requests += 1
        if duration_ms > 0:
            conn.total_duration_ms += duration_ms

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
                record_request('connection_close', duration_ms, success=True)
                logger.debug(f"Закрыто gRPC соединение {key}")
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                record_request('connection_close', duration_ms, success=False, error=str(e))
                raise

    def close_all(self):
        """Закрыть все соединения"""
        for key in list(self.connections.keys()):
            self._close_connection(key)
        logger.info("Все gRPC соединения закрыты")

    def cleanup_idle(self):
        """Очистка неактивных соединений"""
        now = datetime.now()
        for key, conn in list(self.connections.items()):
            idle_seconds = (now - conn.last_used).total_seconds()
            if idle_seconds > self.idle_timeout:
                self._close_connection(key)
                logger.debug(f"Очищено простаивающее соединение {key} ({idle_seconds:.0f} сек)")

    def get_stats(self) -> dict:
        """Получить статистику пула"""
        connections_stats = []
        for key, conn in self.connections.items():
            avg_duration = conn.total_duration_ms / conn.total_requests if conn.total_requests > 0 else 0
            connections_stats.append({
                'key': key,
                'created_at': conn.created_at.isoformat(),
                'last_used': conn.last_used.isoformat(),
                'idle_seconds': (datetime.now() - conn.last_used).total_seconds(),
                'active': conn.active,
                'total_requests': conn.total_requests,
                'failed_requests': conn.failed_requests,
                'success_rate': (conn.total_requests - conn.failed_requests) / conn.total_requests if conn.total_requests > 0 else 0,
                'avg_response_time_ms': avg_duration
            })

        return {
            'total_connections': len(self.connections),
            'max_connections': self.max_connections,
            'idle_timeout': self.idle_timeout,
            'connections': connections_stats,
            'pool_metrics': self._metrics.get_stats()
        }

    def get_load(self) -> float:
        """Получить текущую загрузку пула"""
        if self.max_connections == 0:
            return 0.0
        return len(self.connections) / self.max_connections


# Глобальный пул (синглтон)
_default_pool = None

def get_pool(host='localhost', port=50051, max_connections=10, idle_timeout=300) -> ConnectionPool:
    """Получить глобальный пул соединений"""
    global _default_pool
    if _default_pool is None:
        _default_pool = ConnectionPool(host, port, max_connections, idle_timeout)
    return _default_pool

def close_pool():
    """Закрыть глобальный пул"""
    global _default_pool
    if _default_pool:
        _default_pool.close_all()
        _default_pool = None