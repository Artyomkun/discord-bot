#!/usr/bin/env python3
"""
Пул gRPC серверов (воркеров) для обработки нескольких клиентов
"""

import logging
import threading
import time
from typing import Optional,Dict
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from GRPC.Python.generated.v1 import discord_pb2_grpc
from .server import GrpcServer
from .protocol import DiscordServicer
from concurrent import futures

# Добавляем метрики
from server.metrics import get_metrics_collector, record_request

logger = logging.getLogger(__name__)


class WorkerStatus(Enum):
    """Статус воркера"""
    IDLE = "idle"
    BUSY = "busy"
    STOPPED = "stopped"
    ERROR = "error"


@dataclass
class Worker:
    """Информация о воркере"""
    id: int
    server: GrpcServer
    port: int
    status: WorkerStatus = WorkerStatus.IDLE
    start_time: datetime = field(default_factory=datetime.now)
    last_used: datetime = field(default_factory=datetime.now)
    tasks_processed: int = 0
    errors: int = 0
    total_duration_ms: float = 0.0


class WorkerPool:
    """Пул gRPC воркеров для обработки запросов"""

    def __init__(self, 
                 host='0.0.0.0', 
                 start_port=50051, 
                 max_workers=4,
                 min_workers=2,
                 auto_scale=True):
        self.host = host
        self.start_port = start_port
        self.max_workers = max_workers
        self.min_workers = min_workers
        self.auto_scale = auto_scale
        self.workers: Dict[int, Worker] = {}
        self._lock = threading.Lock()
        self._next_id = 1
        self._servicer_class = None
        self._running = False
        self._metrics = get_metrics_collector()

    def set_servicer(self, servicer_class):
        """Установить класс сервиса"""
        self._servicer_class = servicer_class
        return self

    def _create_worker(self) -> Worker:
        """Создать нового воркера"""
        port = self.start_port + len(self.workers)
        server = GrpcServer(futures.ThreadPoolExecutor(max_workers=10))
        
        if self._servicer_class:
            discord_pb2_grpc.add_DiscordServiceServicer_to_server(
                self._servicer_class(), server
            )
        
        server.add_insecure_port(f'{self.host}:{port}')
        
        worker = Worker(
            id=self._next_id,
            server=server,
            port=port
        )
        self._next_id += 1
        
        with self._lock:
            self.workers[worker.id] = worker
        
        logger.info(f"✅ Создан воркер {worker.id} на порту {port}")
        return worker

    def _start_worker(self, worker: Worker):
        """Запустить воркера"""
        start_time = time.time()
        try:
            worker.server.start()
            worker.status = WorkerStatus.IDLE
            duration_ms = (time.time() - start_time) * 1000
            record_request('worker_start', duration_ms, success=True)
            logger.debug(f"Воркер {worker.id} запущен")
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request('worker_start', duration_ms, success=False, error=str(e))
            raise

    def _stop_worker(self, worker: Worker):
        """Остановить воркера"""
        start_time = time.time()
        try:
            worker.status = WorkerStatus.STOPPED
            worker.server.stop(5)
            with self._lock:
                del self.workers[worker.id]
            duration_ms = (time.time() - start_time) * 1000
            record_request('worker_stop', duration_ms, success=True)
            logger.info(f"🛑 Воркер {worker.id} остановлен")
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request('worker_stop', duration_ms, success=False, error=str(e))
            raise

    def start(self):
        """Запустить пул воркеров"""
        self._running = True
        for _ in range(self.min_workers):
            worker = self._create_worker()
            self._start_worker(worker)
        logger.info(f"🚀 Пул воркеров запущен: {len(self.workers)} воркеров")

    def stop(self):
        """Остановить пул воркеров"""
        self._running = False
        for worker in list(self.workers.values()):
            self._stop_worker(worker)
        logger.info("🛑 Пул воркеров остановлен")

    def get_worker(self) -> Optional[Worker]:
        """Получить свободного воркера"""
        with self._lock:
            idle_workers = [w for w in self.workers.values() if w.status == WorkerStatus.IDLE]
            if idle_workers:
                worker = idle_workers[0]
                worker.status = WorkerStatus.BUSY
                worker.last_used = datetime.now()
                return worker

        # Автомасштабирование
        if self.auto_scale and len(self.workers) < self.max_workers:
            worker = self._create_worker()
            self._start_worker(worker)
            worker.status = WorkerStatus.BUSY
            return worker

        return None

    def release_worker(self, worker: Worker, error: bool = False, duration_ms: float = 0):
        """Освободить воркера"""
        worker.tasks_processed += 1
        worker.total_duration_ms += duration_ms
        if error:
            worker.errors += 1
        worker.status = WorkerStatus.IDLE
        worker.last_used = datetime.now()

        # Записываем метрику обработки
        record_request(f'worker_task_{worker.id}', duration_ms, success=not error)

        # Автомасштабирование вниз
        if self.auto_scale and len(self.workers) > self.min_workers:
            idle_count = len([w for w in self.workers.values() if w.status == WorkerStatus.IDLE])
            if idle_count > 1:
                to_stop = [w for w in self.workers.values() if w.status == WorkerStatus.IDLE][0]
                self._stop_worker(to_stop)

    def get_stats(self) -> dict:
        """Получить статистику пула"""
        with self._lock:
            workers_stats = []
            for w in self.workers.values():
                avg_duration = w.total_duration_ms / w.tasks_processed if w.tasks_processed > 0 else 0
                workers_stats.append({
                    'id': w.id,
                    'port': w.port,
                    'status': w.status.value,
                    'tasks_processed': w.tasks_processed,
                    'errors': w.errors,
                    'error_rate': w.errors / w.tasks_processed if w.tasks_processed > 0 else 0,
                    'avg_task_duration_ms': avg_duration,
                    'uptime_seconds': (datetime.now() - w.start_time).total_seconds(),
                    'idle_seconds': (datetime.now() - w.last_used).total_seconds()
                })

            return {
                'total_workers': len(self.workers),
                'min_workers': self.min_workers,
                'max_workers': self.max_workers,
                'auto_scale': self.auto_scale,
                'load': self.get_load(),
                'workers': workers_stats
            }

    def get_load(self) -> float:
        """Получить текущую загрузку (0-1)"""
        with self._lock:
            if not self.workers:
                return 0.0
            busy = len([w for w in self.workers.values() if w.status == WorkerStatus.BUSY])
            return busy / len(self.workers)


class WorkerPoolServer:
    """Сервер, использующий пул воркеров"""

    def __init__(self, bot, host='0.0.0.0', start_port=50051, max_workers=4, min_workers=2):
        self.bot = bot
        self.pool = WorkerPool(host, start_port, max_workers, min_workers)
        self.pool.set_servicer(lambda: self._create_servicer())
        self._metrics = get_metrics_collector()

    def _create_servicer(self):
        """Создать сервис для воркера"""
        return DiscordServicer(self.bot)

    def start(self):
        """Запустить сервер"""
        self.pool.start()
        logger.info("✅ WorkerPoolServer запущен")

    def stop(self):
        """Остановить сервер"""
        self.pool.stop()
        logger.info("🛑 WorkerPoolServer остановлен")

    def get_stats(self) -> dict:
        """Получить статистику"""
        stats = self.pool.get_stats()
        stats['global_metrics'] = self._metrics.get_stats()
        return stats

    async def health_check(self) -> dict:
        """Проверка здоровья сервера"""
        return {
            'status': 'healthy',
            'workers': self.pool.get_load(),
            'total_workers': len(self.pool.workers),
            'active_workers': len([w for w in self.pool.workers.values() if w.status == WorkerStatus.BUSY])
        }


# Глобальный пул (синглтон)
_default_pool = None

def get_pool(bot=None, host='0.0.0.0', start_port=50051, max_workers=4, min_workers=2) -> WorkerPoolServer:
    """Получить глобальный пул серверов"""
    global _default_pool
    if _default_pool is None and bot is not None:
        _default_pool = WorkerPoolServer(bot, host, start_port, max_workers, min_workers)
    return _default_pool

def start_pool(bot, host='0.0.0.0', start_port=50051, max_workers=4, min_workers=2):
    """Запустить глобальный пул"""
    global _default_pool
    _default_pool = WorkerPoolServer(bot, host, start_port, max_workers, min_workers)
    _default_pool.start()
    return _default_pool

def stop_pool():
    """Остановить глобальный пул"""
    global _default_pool
    if _default_pool:
        _default_pool.stop()
        _default_pool = None