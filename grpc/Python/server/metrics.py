#!/usr/bin/env python3
"""
Метрики для gRPC сервера с интеграцией клиентских метрик и принятием решений
"""

import time
import threading
import logging
import json
import os
from datetime import datetime
from typing import Dict, List, Optional, Callable
from collections import deque
from dataclasses import dataclass, field
from enum import Enum

logger = logging.getLogger(__name__)


class ErrorType(Enum):
    """Тип ошибки"""
    SERVER = "server"
    CLIENT = "client"
    NETWORK = "network"
    DATABASE = "database"
    GRPC = "grpc"
    UNRESOLVED = "unresolved"  # Добавляем тип для нерешённых задач


class Resolution(Enum):
    """Решение по ошибке"""
    IGNORE = "ignore"
    RETRY = "retry"
    FALLBACK = "fallback"
    ALERT = "alert"
    RESTART = "restart"
    SHUTDOWN = "shutdown"
    NOTIFY_CLIENT = "notify_client"
    INCREASE_TIMEOUT = "increase_timeout"
    DECREASE_TIMEOUT = "decrease_timeout"
    SWITCH_BACKEND = "switch_backend"
    ESCALATE = "escalate"  # Эскалация для нерешённых задач


@dataclass
class ErrorRecord:
    """Запись об ошибке для дашборда"""
    timestamp: float
    error_type: ErrorType
    method: str
    error: str
    client_id: Optional[str]
    resolution: Optional[Resolution]
    resolved: bool = False
    resolved_at: Optional[float] = None
    notes: Optional[str] = None
    source: str = "server"  # server или client


@dataclass
class UnresolvedTask:
    """Неразрешённая задача от клиента"""
    task_id: str
    error_type: str
    error: str
    method: str
    client_id: str
    timestamp: float
    retry_count: int = 0
    received_at: float = field(default_factory=time.time)
    status: str = "pending"  # pending, processing, resolved


@dataclass
class RequestMetrics:
    """Метрики одного запроса"""
    method: str
    start_time: float
    end_time: Optional[float] = None
    success: bool = True
    error: Optional[str] = None
    client: Optional[str] = None
    error_type: Optional[ErrorType] = None

    @property
    def duration_ms(self) -> float:
        if self.end_time:
            return (self.end_time - self.start_time) * 1000
        return 0


class MetricsCollector:
    """Сборщик метрик с интеграцией клиентских ошибок и принятием решений"""

    def __init__(self, window_size: int = 1000, dashboard_dir: str = "/tmp/grpc_dashboard",
                 api_port: int = 8080):
        self._lock = threading.Lock()
        self.window_size = window_size
        self.requests: deque = deque(maxlen=window_size)
        self.total_requests = 0
        self.successful_requests = 0
        self.failed_requests = 0
        self.start_time = time.time()
        self._method_stats: Dict[str, Dict] = {}
        self._rate_limit_hits: Dict[str, int] = {}
        self._client_errors: Dict[str, int] = {}
        self._client_metrics_client = None
        self._client_error_handlers: List[Callable] = []
        self._error_records: List[ErrorRecord] = []
        self._dashboard_dir = dashboard_dir
        self._resolution_handlers: Dict[Resolution, List[Callable]] = {}
        self._error_counters: Dict[str, int] = {}
        self._last_resolution_time: Dict[str, float] = {}
        self._unresolved_tasks: Dict[str, UnresolvedTask] = {}
        self._api_port = api_port
        self._running = True
        
        # Создаём папку для дашборда
        os.makedirs(dashboard_dir, exist_ok=True)
        
        # Пороги для принятия решений
        self.thresholds = {
            'error_rate_warning': 0.05,      # 5%
            'error_rate_critical': 0.1,      # 10%
            'client_error_rate_warning': 0.1, # 10% ошибок от одного клиента
            'client_error_rate_critical': 0.2, # 20%
            'consecutive_errors': 5,
            'time_window_seconds': 60,
            'unresolved_task_ttl': 3600,  # 1 час на решение задачи
            'unresolved_alert_threshold': 3,  # 3 нерешённые задачи
        }
        
        # Запускаем API для приёма задач от клиента
        self._start_api_server()

    def _start_api_server(self):
        """Запустить API сервер для приёма задач от клиента"""
        import threading
        from flask import Flask, request, jsonify
        
        app = Flask(__name__)
        
        @app.route('/api/unresolved_task', methods=['POST'])
        def receive_unresolved_task():
            """Принять нерешённую задачу от клиента"""
            try:
                data = request.get_json()
                task = UnresolvedTask(
                    task_id=data.get('task_id'),
                    error_type=data.get('error_type'),
                    error=data.get('error'),
                    method=data.get('method'),
                    client_id=data.get('client_id'),
                    timestamp=data.get('timestamp'),
                    retry_count=data.get('retry_count', 0)
                )
                
                with self._lock:
                    self._unresolved_tasks[task.task_id] = task
                
                logger.warning(f"📥 Получена нерешённая задача от клиента {task.client_id}: {task.error[:100]}")
                
                # Создаём запись об ошибке
                error_record = ErrorRecord(
                    timestamp=time.time(),
                    error_type=ErrorType.UNRESOLVED,
                    method=task.method,
                    error=f"Unresolved from client: {task.error}",
                    client_id=task.client_id,
                    resolution=None,
                    resolved=False,
                    source="client"
                )
                self._error_records.append(error_record)
                self._save_to_dashboard(error_record)
                
                # Принимаем решение по задаче
                self._process_unresolved_task(task)
                
                return jsonify({'status': 'ok'}), 200
                
            except Exception as e:
                logger.error(f"Ошибка приёма нерешённой задачи: {e}")
                return jsonify({'error': str(e)}), 500
        
        @app.route('/api/critical_alert', methods=['POST'])
        def receive_critical_alert():
            """Принять критическое уведомление от клиента"""
            try:
                data = request.get_json()
                logger.critical(f"🔴 Критическое уведомление от клиента: {data}")
                
                # Создаём запись об ошибке
                error_record = ErrorRecord(
                    timestamp=time.time(),
                    error_type=ErrorType.CLIENT,
                    method="critical_alert",
                    error=f"Critical alert from client: {data.get('error_count', 0)} errors",
                    client_id=data.get('client_id'),
                    resolution=Resolution.ESCALATE,
                    resolved=False,
                    source="client"
                )
                self._error_records.append(error_record)
                self._save_to_dashboard(error_record)
                
                return jsonify({'status': 'ok'}), 200
                
            except Exception as e:
                logger.error(f"Ошибка приёма критического уведомления: {e}")
                return jsonify({'error': str(e)}), 500
        
        # Запускаем Flask в отдельном потоке
        def run_flask():
            app.run(host='0.0.0.0', port=self._api_port, debug=False)
        
        thread = threading.Thread(target=run_flask, daemon=True)
        thread.start()
        logger.info(f"🚀 API сервер метрик запущен на порту {self._api_port}")

    def _process_unresolved_task(self, task: UnresolvedTask):
        """Обработать нерешённую задачу от клиента"""
        logger.info(f"🔧 Обработка нерешённой задачи {task.task_id} от клиента {task.client_id}")
        
        # Создаём запись об ошибке для принятия решения
        error_record = ErrorRecord(
            timestamp=time.time(),
            error_type=ErrorType.CLIENT,
            method=task.method,
            error=task.error,
            client_id=task.client_id,
            resolution=None,
            resolved=False,
            source="client"
        )
        
        # Принимаем решение
        resolution = self._decide_resolution(error_record)
        
        # Если решение требует эскалации
        if resolution == Resolution.ESCALATE or task.retry_count >= 3:
            self._escalate_unresolved_task(task)
        
        # Отправляем команду клиенту
        self._send_command_to_client(task.client_id, resolution, task.task_id)
        
        # Отмечаем задачу как обработанную
        with self._lock:
            if task.task_id in self._unresolved_tasks:
                self._unresolved_tasks[task.task_id].status = "resolved"

    def _escalate_unresolved_task(self, task: UnresolvedTask):
        """Эскалация нерешённой задачи"""
        logger.critical(f"🚨 ЭСКАЛАЦИЯ: Нерешённая задача {task.task_id} от клиента {task.client_id}")
        
        # Создаём критическую запись
        error_record = ErrorRecord(
            timestamp=time.time(),
            error_type=ErrorType.CLIENT,
            method=task.method,
            error=f"ESCALATED: {task.error}",
            client_id=task.client_id,
            resolution=Resolution.ESCALATE,
            resolved=False,
            source="client"
        )
        self._error_records.append(error_record)
        self._save_to_dashboard(error_record)
        
        # Вызываем обработчики эскалации
        if Resolution.ESCALATE in self._resolution_handlers:
            for handler in self._resolution_handlers[Resolution.ESCALATE]:
                try:
                    handler(error_record)
                except Exception as e:
                    logger.error(f"Ошибка в обработчике эскалации: {e}")

    def _send_command_to_client(self, client_id: str, resolution: Resolution, task_id: str):
        """Отправить команду клиенту"""
        if self._client_metrics_client:
            try:
                command_map = {
                    Resolution.RETRY: 'increase_retry',
                    Resolution.INCREASE_TIMEOUT: 'increase_timeout',
                    Resolution.DECREASE_TIMEOUT: 'decrease_timeout',
                    Resolution.SWITCH_BACKEND: 'switch_backend',
                    Resolution.RESTART: 'reconnect',
                }
                
                command = command_map.get(resolution, 'report_status')
                
                self._client_metrics_client.receive_server_command({
                    'command': command,
                    'params': {
                        'task_id': task_id,
                        'resolution': resolution.value,
                        'reason': 'unresolved_task'
                    },
                    'source': 'server_metrics'
                })
                logger.info(f"📤 Отправлена команда {command} клиенту {client_id}")
            except Exception as e:
                logger.error(f"Ошибка отправки команды клиенту: {e}")

    def set_client_metrics(self, client_metrics):
        """Установить клиентские метрики для передачи ошибок"""
        self._client_metrics_client = client_metrics

    def add_client_error_handler(self, handler: Callable):
        """Добавить обработчик клиентских ошибок"""
        self._client_error_handlers.append(handler)

    def register_resolution_handler(self, resolution: Resolution, handler: Callable):
        """Зарегистрировать обработчик для решения"""
        if resolution not in self._resolution_handlers:
            self._resolution_handlers[resolution] = []
        self._resolution_handlers[resolution].append(handler)

    def _execute_resolution(self, resolution: Resolution, error_record: ErrorRecord):
        """Выполнить решение"""
        logger.info(f"🔧 Применяем решение: {resolution.value} для ошибки: {error_record.error[:100]}")
        
        error_record.resolution = resolution
        
        # Вызываем обработчики
        if resolution in self._resolution_handlers:
            for handler in self._resolution_handlers[resolution]:
                try:
                    handler(error_record)
                except Exception as e:
                    logger.error(f"Ошибка в обработчике решения {resolution.value}: {e}")
        
        # Стандартные действия
        if resolution == Resolution.NOTIFY_CLIENT:
            self._notify_client_about_error(error_record)
        elif resolution == Resolution.INCREASE_TIMEOUT:
            self._increase_timeout()
        elif resolution == Resolution.DECREASE_TIMEOUT:
            self._decrease_timeout()
        elif resolution == Resolution.SWITCH_BACKEND:
            self._switch_backend()

    def _decide_resolution(self, error_record: ErrorRecord) -> Resolution:
        """Принять решение по ошибке"""
        error_type = error_record.error_type
        error_msg = error_record.error.lower()
        client_id = error_record.client_id
        source = error_record.source
        
        # Для нерешённых задач от клиента
        if source == "client" or error_type == ErrorType.UNRESOLVED:
            return Resolution.ESCALATE
        
        # Проверяем частоту ошибок от клиента
        if client_id:
            client_errors = self._error_counters.get(f"client_{client_id}", 0)
            if client_errors > self.thresholds['client_error_rate_critical'] * 100:
                return Resolution.NOTIFY_CLIENT
            if client_errors > self.thresholds['client_error_rate_warning'] * 100:
                return Resolution.ALERT
        
        # По типу ошибки
        if error_type == ErrorType.CLIENT:
            return Resolution.NOTIFY_CLIENT
            
        elif error_type == ErrorType.NETWORK:
            if "timeout" in error_msg:
                return Resolution.INCREASE_TIMEOUT
            return Resolution.RETRY
            
        elif error_type == ErrorType.DATABASE:
            return Resolution.FALLBACK
            
        elif error_type == ErrorType.GRPC:
            return Resolution.RESTART
            
        elif error_type == ErrorType.SERVER:
            # Проверяем последовательные ошибки
            key = f"{error_record.method}_{error_record.error[:50]}"
            consecutive = self._error_counters.get(key, 0)
            if consecutive > self.thresholds['consecutive_errors']:
                return Resolution.RESTART
            return Resolution.RETRY
        
        # По содержимому ошибки
        if "memory" in error_msg or "out of memory" in error_msg:
            return Resolution.RESTART
        if "connection refused" in error_msg or "connection reset" in error_msg:
            return Resolution.RETRY
        if "rate limit" in error_msg or "too many requests" in error_msg:
            return Resolution.ALERT
        if "unauthorized" in error_msg or "forbidden" in error_msg:
            return Resolution.ALERT
        
        return Resolution.IGNORE

    def _notify_client_about_error(self, error_record: ErrorRecord):
        """Уведомить клиент о проблеме"""
        if self._client_metrics_client:
            try:
                self._client_metrics_client.receive_server_command({
                    'command': 'report_status',
                    'params': {
                        'error': error_record.error,
                        'error_type': error_record.error_type.value,
                        'method': error_record.method,
                        'resolution': error_record.resolution.value if error_record.resolution else None
                    },
                    'source': 'server_metrics'
                })
            except Exception as e:
                logger.error(f"Ошибка уведомления клиента: {e}")

    def _increase_timeout(self):
        """Увеличить таймаут"""
        logger.info("⏱️ Увеличиваем таймаут")
        if self._client_metrics_client:
            try:
                self._client_metrics_client.receive_server_command({
                    'command': 'increase_timeout',
                    'params': {'reason': 'server_decision'},
                    'source': 'server_metrics'
                })
            except Exception as e:
                logger.error(f"Ошибка увеличения таймаута: {e}")

    def _decrease_timeout(self):
        """Уменьшить таймаут"""
        logger.info("⏱️ Уменьшаем таймаут")
        if self._client_metrics_client:
            try:
                self._client_metrics_client.receive_server_command({
                    'command': 'decrease_timeout',
                    'params': {'reason': 'server_decision'},
                    'source': 'server_metrics'
                })
            except Exception as e:
                logger.error(f"Ошибка уменьшения таймаута: {e}")

    def _switch_backend(self):
        """Переключить бэкенд"""
        logger.info("🔄 Переключаем бэкенд")
        if self._client_metrics_client:
            try:
                self._client_metrics_client.receive_server_command({
                    'command': 'switch_backend',
                    'params': {'backend': 'fallback'},
                    'source': 'server_metrics'
                })
            except Exception as e:
                logger.error(f"Ошибка переключения бэкенда: {e}")

    def _notify_client_error(self, client_id: str, error: str, method: str = None):
        """Уведомить клиентские метрики об ошибке и принять решение"""
        if self._client_metrics_client:
            try:
                self._client_metrics_client.record_external_error(client_id, error, method)
            except Exception as e:
                logger.error(f"Ошибка передачи ошибки в клиентские метрики: {e}")
        
        for handler in self._client_error_handlers:
            try:
                handler(client_id, error, method)
            except Exception as e:
                logger.error(f"Ошибка в обработчике клиентских ошибок: {e}")

    def _save_to_dashboard(self, error_record: ErrorRecord):
        """Сохранить запись в дашборд"""
        try:
            filename = f"{self._dashboard_dir}/errors_{datetime.now().strftime('%Y%m%d')}.json"
            data = {
                'timestamp': error_record.timestamp,
                'datetime': datetime.fromtimestamp(error_record.timestamp).isoformat(),
                'error_type': error_record.error_type.value,
                'method': error_record.method,
                'error': error_record.error,
                'client_id': error_record.client_id,
                'resolution': error_record.resolution.value if error_record.resolution else None,
                'resolved': error_record.resolved,
                'resolved_at': error_record.resolved_at,
                'notes': error_record.notes,
                'source': error_record.source
            }
            
            existing = []
            if os.path.exists(filename):
                try:
                    with open(filename, 'r') as f:
                        existing = json.load(f)
                except:
                    pass
            
            existing.append(data)
            
            with open(filename, 'w') as f:
                json.dump(existing, f, indent=2)
                
        except Exception as e:
            logger.error(f"Ошибка сохранения в дашборд: {e}")

    def record_request(self, method: str, duration_ms: float, success: bool = True, 
                       error: str = None, client_id: str = None, 
                       error_type: ErrorType = ErrorType.SERVER):
        """Записать метрики запроса"""
        with self._lock:
            self.total_requests += 1
            if success:
                self.successful_requests += 1
            else:
                self.failed_requests += 1
                if client_id:
                    self._client_errors[client_id] = self._client_errors.get(client_id, 0) + 1
                
                error_record = ErrorRecord(
                    timestamp=time.time(),
                    error_type=error_type,
                    method=method,
                    error=error or "Unknown error",
                    client_id=client_id,
                    resolution=None,
                    resolved=False,
                    source="server"
                )
                
                key = f"{method}_{error[:50]}" if error else method
                self._error_counters[key] = self._error_counters.get(key, 0) + 1
                
                resolution = self._decide_resolution(error_record)
                self._execute_resolution(resolution, error_record)
                
                self._save_to_dashboard(error_record)
                self._error_records.append(error_record)
                
                if error_type == ErrorType.CLIENT and client_id:
                    self._notify_client_error(client_id, error, method)

            self.requests.append({
                'method': method,
                'duration_ms': duration_ms,
                'success': success,
                'error': error,
                'client_id': client_id,
                'error_type': error_type.value if error_type else None,
                'timestamp': time.time()
            })

            if method not in self._method_stats:
                self._method_stats[method] = {
                    'total': 0,
                    'success': 0,
                    'failed': 0,
                    'total_duration': 0,
                    'min_duration': float('inf'),
                    'max_duration': 0,
                    'client_errors': 0,
                    'server_errors': 0,
                    'network_errors': 0,
                    'unresolved_errors': 0
                }

            stats = self._method_stats[method]
            stats['total'] += 1
            if success:
                stats['success'] += 1
            else:
                stats['failed'] += 1
                if error_type == ErrorType.CLIENT:
                    stats['client_errors'] += 1
                elif error_type == ErrorType.SERVER:
                    stats['server_errors'] += 1
                elif error_type == ErrorType.NETWORK:
                    stats['network_errors'] += 1
                elif error_type == ErrorType.UNRESOLVED:
                    stats['unresolved_errors'] += 1
            
            stats['total_duration'] += duration_ms
            stats['min_duration'] = min(stats['min_duration'], duration_ms)
            stats['max_duration'] = max(stats['max_duration'], duration_ms)

    def record_client_error(self, client_id: str, error: str = None, method: str = None):
        """Записать ошибку клиента"""
        with self._lock:
            self._client_errors[client_id] = self._client_errors.get(client_id, 0) + 1
            if method and method in self._method_stats:
                self._method_stats[method]['client_errors'] = self._method_stats[method].get('client_errors', 0) + 1
            
            error_record = ErrorRecord(
                timestamp=time.time(),
                error_type=ErrorType.CLIENT,
                method=method or "unknown",
                error=error or "Client error",
                client_id=client_id,
                resolution=None,
                resolved=False,
                source="server"
            )
            
            resolution = self._decide_resolution(error_record)
            self._execute_resolution(resolution, error_record)
            self._save_to_dashboard(error_record)
            self._error_records.append(error_record)
            
            self._notify_client_error(client_id, error, method)

    def record_server_error(self, error: str, method: str = None):
        """Записать серверную ошибку"""
        with self._lock:
            if method and method in self._method_stats:
                self._method_stats[method]['server_errors'] = self._method_stats[method].get('server_errors', 0) + 1
            
            error_record = ErrorRecord(
                timestamp=time.time(),
                error_type=ErrorType.SERVER,
                method=method or "unknown",
                error=error,
                client_id=None,
                resolution=None,
                resolved=False,
                source="server"
            )
            
            resolution = self._decide_resolution(error_record)
            self._execute_resolution(resolution, error_record)
            self._save_to_dashboard(error_record)
            self._error_records.append(error_record)

    def record_network_error(self, error: str, method: str = None):
        """Записать сетевую ошибку"""
        with self._lock:
            if method and method in self._method_stats:
                self._method_stats[method]['network_errors'] = self._method_stats[method].get('network_errors', 0) + 1
            
            error_record = ErrorRecord(
                timestamp=time.time(),
                error_type=ErrorType.NETWORK,
                method=method or "unknown",
                error=error,
                client_id=None,
                resolution=None,
                resolved=False,
                source="server"
            )
            
            resolution = self._decide_resolution(error_record)
            self._execute_resolution(resolution, error_record)
            self._save_to_dashboard(error_record)
            self._error_records.append(error_record)

    def record_rate_limit(self, method: str, client: str = None):
        """Записать срабатывание rate limit"""
        with self._lock:
            key = f"{method}:{client}" if client else method
            self._rate_limit_hits[key] = self._rate_limit_hits.get(key, 0) + 1

    def mark_error_resolved(self, error_index: int, notes: str = None):
        """Отметить ошибку как решённую"""
        with self._lock:
            if 0 <= error_index < len(self._error_records):
                self._error_records[error_index].resolved = True
                self._error_records[error_index].resolved_at = time.time()
                self._error_records[error_index].notes = notes
                self._save_to_dashboard(self._error_records[error_index])

    def get_unresolved_tasks(self) -> List[Dict]:
        """Получить нерешённые задачи от клиентов"""
        with self._lock:
            return [
                {
                    'task_id': task.task_id,
                    'error_type': task.error_type,
                    'error': task.error,
                    'method': task.method,
                    'client_id': task.client_id,
                    'timestamp': task.timestamp,
                    'retry_count': task.retry_count,
                    'status': task.status
                }
                for task in self._unresolved_tasks.values()
            ]

    def get_dashboard(self) -> dict:
        """Получить дашборд ошибок"""
        with self._lock:
            unresolved_from_clients = [e for e in self._error_records if e.source == "client" and not e.resolved]
            
            return {
                'total_errors': len(self._error_records),
                'unresolved_errors': sum(1 for e in self._error_records if not e.resolved),
                'unresolved_from_clients': len(unresolved_from_clients),
                'errors_by_type': {
                    ErrorType.SERVER.value: sum(1 for e in self._error_records if e.error_type == ErrorType.SERVER),
                    ErrorType.CLIENT.value: sum(1 for e in self._error_records if e.error_type == ErrorType.CLIENT),
                    ErrorType.NETWORK.value: sum(1 for e in self._error_records if e.error_type == ErrorType.NETWORK),
                    ErrorType.DATABASE.value: sum(1 for e in self._error_records if e.error_type == ErrorType.DATABASE),
                    ErrorType.GRPC.value: sum(1 for e in self._error_records if e.error_type == ErrorType.GRPC),
                    ErrorType.UNRESOLVED.value: sum(1 for e in self._error_records if e.error_type == ErrorType.UNRESOLVED),
                },
                'errors_by_method': self._get_errors_by_method(),
                'errors_by_source': {
                    'server': sum(1 for e in self._error_records if e.source == "server"),
                    'client': sum(1 for e in self._error_records if e.source == "client"),
                },
                'unresolved_tasks': self.get_unresolved_tasks(),
                'recent_errors': [
                    {
                        'timestamp': e.timestamp,
                        'datetime': datetime.fromtimestamp(e.timestamp).isoformat(),
                        'error_type': e.error_type.value,
                        'method': e.method,
                        'error': e.error[:200],
                        'client_id': e.client_id,
                        'resolution': e.resolution.value if e.resolution else None,
                        'resolved': e.resolved,
                        'source': e.source
                    }
                    for e in self._error_records[-50:]
                ]
            }

    def _get_errors_by_method(self) -> Dict[str, int]:
        """Получить количество ошибок по методам"""
        errors = {}
        for e in self._error_records:
            errors[e.method] = errors.get(e.method, 0) + 1
        return errors

    def get_stats(self) -> dict:
        """Получить текущую статистику"""
        with self._lock:
            uptime = time.time() - self.start_time
            
            now = time.time()
            recent_requests = [r for r in self.requests if now - r['timestamp'] <= 60]
            avg_recent_duration = sum(r['duration_ms'] for r in recent_requests) / len(recent_requests) if recent_requests else 0
            rps = len(recent_requests) / 60 if recent_requests else 0

            stats = {
                'uptime_seconds': uptime,
                'total_requests': self.total_requests,
                'successful_requests': self.successful_requests,
                'failed_requests': self.failed_requests,
                'client_errors': sum(self._client_errors.values()),
                'unresolved_tasks': len(self._unresolved_tasks),
                'success_rate': self.successful_requests / self.total_requests if self.total_requests > 0 else 0,
                'requests_per_second': rps,
                'avg_response_time_ms': avg_recent_duration,
                'methods': {}
            }

            for method, s in self._method_stats.items():
                stats['methods'][method] = {
                    'total': s['total'],
                    'success': s['success'],
                    'failed': s['failed'],
                    'client_errors': s.get('client_errors', 0),
                    'server_errors': s.get('server_errors', 0),
                    'network_errors': s.get('network_errors', 0),
                    'unresolved_errors': s.get('unresolved_errors', 0),
                    'avg_duration_ms': s['total_duration'] / s['total'] if s['total'] > 0 else 0,
                    'min_duration_ms': s['min_duration'] if s['min_duration'] != float('inf') else 0,
                    'max_duration_ms': s['max_duration']
                }

            if self._rate_limit_hits:
                stats['rate_limit_hits'] = self._rate_limit_hits

            if self._client_errors:
                stats['client_errors_by_id'] = dict(self._client_errors)

            return stats

    def get_correlation_stats(self, client_id: str = None) -> dict:
        """Получить корреляционную статистику для клиента"""
        with self._lock:
            if client_id:
                client_requests = [r for r in self.requests if r.get('client_id') == client_id]
            else:
                client_requests = list(self.requests)
            
            if not client_requests:
                return {'total': 0, 'success': 0, 'failed': 0}
            
            total = len(client_requests)
            success = sum(1 for r in client_requests if r['success'])
            failed = total - success
            
            return {
                'total': total,
                'success': success,
                'failed': failed,
                'success_rate': success / total if total > 0 else 0,
                'avg_duration_ms': sum(r['duration_ms'] for r in client_requests) / total if total > 0 else 0
            }

    def reset(self):
        """Сбросить метрики"""
        with self._lock:
            self.requests.clear()
            self.total_requests = 0
            self.successful_requests = 0
            self.failed_requests = 0
            self.start_time = time.time()
            self._method_stats.clear()
            self._rate_limit_hits.clear()
            self._client_errors.clear()
            self._error_records.clear()
            self._error_counters.clear()
            self._unresolved_tasks.clear()


class MetricsExporter:
    """Экспорт метрик в различных форматах"""

    def __init__(self, collector: MetricsCollector):
        self.collector = collector

    def to_prometheus(self) -> str:
        """Экспорт в формате Prometheus"""
        stats = self.collector.get_stats()
        dashboard = self.collector.get_dashboard()
        lines = []

        lines.append(f"# HELP grpc_total_requests Total number of gRPC requests")
        lines.append(f"# TYPE grpc_total_requests counter")
        lines.append(f"grpc_total_requests {stats['total_requests']}")

        lines.append(f"# HELP grpc_successful_requests Successful gRPC requests")
        lines.append(f"# TYPE grpc_successful_requests counter")
        lines.append(f"grpc_successful_requests {stats['successful_requests']}")

        lines.append(f"# HELP grpc_failed_requests Failed gRPC requests")
        lines.append(f"# TYPE grpc_failed_requests counter")
        lines.append(f"grpc_failed_requests {stats['failed_requests']}")

        lines.append(f"# HELP grpc_client_errors Client-side errors")
        lines.append(f"# TYPE grpc_client_errors counter")
        lines.append(f"grpc_client_errors {stats.get('client_errors', 0)}")

        lines.append(f"# HELP grpc_unresolved_tasks Unresolved tasks from clients")
        lines.append(f"# TYPE grpc_unresolved_tasks gauge")
        lines.append(f"grpc_unresolved_tasks {stats.get('unresolved_tasks', 0)}")

        lines.append(f"# HELP grpc_total_errors Total errors recorded")
        lines.append(f"# TYPE grpc_total_errors counter")
        lines.append(f"grpc_total_errors {dashboard['total_errors']}")

        lines.append(f"# HELP grpc_unresolved_errors Unresolved errors")
        lines.append(f"# TYPE grpc_unresolved_errors gauge")
        lines.append(f"grpc_unresolved_errors {dashboard['unresolved_errors']}")

        lines.append(f"# HELP grpc_success_rate Success rate of gRPC requests")
        lines.append(f"# TYPE grpc_success_rate gauge")
        lines.append(f"grpc_success_rate {stats['success_rate']}")

        lines.append(f"# HELP grpc_requests_per_second Requests per second")
        lines.append(f"# TYPE grpc_requests_per_second gauge")
        lines.append(f"grpc_requests_per_second {stats['requests_per_second']}")

        lines.append(f"# HELP grpc_avg_response_time_ms Average response time in ms")
        lines.append(f"# TYPE grpc_avg_response_time_ms gauge")
        lines.append(f"grpc_avg_response_time_ms {stats['avg_response_time_ms']}")

        for method, s in stats['methods'].items():
            method_clean = method.replace('.', '_').replace('/', '_')
            lines.append(f"# HELP grpc_method_total_{method_clean} Total requests for {method}")
            lines.append(f"# TYPE grpc_method_total_{method_clean} counter")
            lines.append(f"grpc_method_total_{method_clean} {s['total']}")

            lines.append(f"# HELP grpc_method_client_errors_{method_clean} Client errors for {method}")
            lines.append(f"# TYPE grpc_method_client_errors_{method_clean} counter")
            lines.append(f"grpc_method_client_errors_{method_clean} {s.get('client_errors', 0)}")

            lines.append(f"# HELP grpc_method_server_errors_{method_clean} Server errors for {method}")
            lines.append(f"# TYPE grpc_method_server_errors_{method_clean} counter")
            lines.append(f"grpc_method_server_errors_{method_clean} {s.get('server_errors', 0)}")

            lines.append(f"# HELP grpc_method_network_errors_{method_clean} Network errors for {method}")
            lines.append(f"# TYPE grpc_method_network_errors_{method_clean} counter")
            lines.append(f"grpc_method_network_errors_{method_clean} {s.get('network_errors', 0)}")

            lines.append(f"# HELP grpc_method_unresolved_errors_{method_clean} Unresolved errors for {method}")
            lines.append(f"# TYPE grpc_method_unresolved_errors_{method_clean} counter")
            lines.append(f"grpc_method_unresolved_errors_{method_clean} {s.get('unresolved_errors', 0)}")

            lines.append(f"# HELP grpc_method_avg_duration_ms_{method_clean} Average duration for {method}")
            lines.append(f"# TYPE grpc_method_avg_duration_ms_{method_clean} gauge")
            lines.append(f"grpc_method_avg_duration_ms_{method_clean} {s['avg_duration_ms']}")

        return '\n'.join(lines)

    def to_json(self) -> dict:
        """Экспорт в JSON"""
        return {
            'stats': self.collector.get_stats(),
            'dashboard': self.collector.get_dashboard()
        }

    def to_text(self) -> str:
        """Экспорт в читаемый текст"""
        stats = self.collector.get_stats()
        dashboard = self.collector.get_dashboard()
        lines = [
            "=" * 50,
            "gRPC Server Metrics",
            "=" * 50,
            f"Uptime: {stats['uptime_seconds']:.0f} seconds",
            f"Total requests: {stats['total_requests']}",
            f"Successful: {stats['successful_requests']}",
            f"Failed: {stats['failed_requests']}",
            f"Client errors: {stats.get('client_errors', 0)}",
            f"Unresolved tasks: {stats.get('unresolved_tasks', 0)}",
            f"Total errors: {dashboard['total_errors']}",
            f"Unresolved errors: {dashboard['unresolved_errors']}",
            f"Unresolved from clients: {dashboard['unresolved_from_clients']}",
            f"Success rate: {stats['success_rate']*100:.1f}%",
            f"RPS: {stats['requests_per_second']:.2f}",
            f"Avg response time: {stats['avg_response_time_ms']:.2f} ms",
            "",
            "Methods:"
        ]

        for method, s in stats['methods'].items():
            lines.append(f"  {method}:")
            lines.append(f"    total: {s['total']}")
            lines.append(f"    client errors: {s.get('client_errors', 0)}")
            lines.append(f"    server errors: {s.get('server_errors', 0)}")
            lines.append(f"    network errors: {s.get('network_errors', 0)}")
            lines.append(f"    unresolved errors: {s.get('unresolved_errors', 0)}")
            lines.append(f"    avg: {s['avg_duration_ms']:.2f} ms")
            lines.append(f"    min: {s['min_duration_ms']:.2f} ms")
            lines.append(f"    max: {s['max_duration_ms']:.2f} ms")

        if stats.get('rate_limit_hits'):
            lines.append("")
            lines.append("Rate limit hits:")
            for key, count in stats['rate_limit_hits'].items():
                lines.append(f"  {key}: {count}")

        if stats.get('client_errors_by_id'):
            lines.append("")
            lines.append("Client errors by ID:")
            for client_id, count in stats['client_errors_by_id'].items():
                lines.append(f"  {client_id}: {count}")

        lines.append("")
        lines.append("Error Dashboard:")
        lines.append(f"  Total errors: {dashboard['total_errors']}")
        lines.append(f"  Unresolved: {dashboard['unresolved_errors']}")
        lines.append(f"  Unresolved from clients: {dashboard['unresolved_from_clients']}")
        lines.append("  Errors by type:")
        for error_type, count in dashboard['errors_by_type'].items():
            lines.append(f"    {error_type}: {count}")
        lines.append("  Errors by source:")
        for source, count in dashboard['errors_by_source'].items():
            lines.append(f"    {source}: {count}")
        lines.append("  Errors by method:")
        for method, count in dashboard['errors_by_method'].items():
            lines.append(f"    {method}: {count}")
        
        if dashboard['unresolved_tasks']:
            lines.append("")
            lines.append("Unresolved tasks from clients:")
            for task in dashboard['unresolved_tasks'][-5:]:
                lines.append(f"  {task['task_id']}: {task['method']} - {task['error'][:50]}...")
        
        if dashboard['recent_errors']:
            lines.append("")
            lines.append("Recent errors (last 5):")
            for e in dashboard['recent_errors'][-5:]:
                lines.append(f"    [{e['datetime']}] {e['source']}:{e['error_type']}: {e['method']} - {e['error'][:50]}...")

        return '\n'.join(lines)


# Глобальный сборщик метрик
_metrics_collector = None


def get_metrics_collector(api_port: int = 8080) -> MetricsCollector:
    """Получить глобальный сборщик метрик"""
    global _metrics_collector
    if _metrics_collector is None:
        _metrics_collector = MetricsCollector(api_port=api_port)
    return _metrics_collector


def record_request(method: str, duration_ms: float, success: bool = True, 
                   error: str = None, client_id: str = None,
                   error_type: ErrorType = ErrorType.SERVER):
    """Удобная функция для записи метрик"""
    get_metrics_collector().record_request(method, duration_ms, success, error, client_id, error_type)


def record_client_error(client_id: str, method: str = None, error: str = None):
    """Записать ошибку клиента"""
    get_metrics_collector().record_client_error(client_id, error, method)


def record_server_error(error: str, method: str = None):
    """Записать серверную ошибку"""
    get_metrics_collector().record_server_error(error, method)


def record_network_error(error: str, method: str = None):
    """Записать сетевую ошибку"""
    get_metrics_collector().record_network_error(error, method)


def record_rate_limit(method: str, client: str = None):
    """Записать срабатывание rate limit"""
    get_metrics_collector().record_rate_limit(method, client)


def set_client_metrics(client_metrics):
    """Установить клиентские метрики для прямой передачи ошибок"""
    get_metrics_collector().set_client_metrics(client_metrics)


def add_client_error_handler(handler: Callable):
    """Добавить обработчик клиентских ошибок"""
    get_metrics_collector().add_client_error_handler(handler)


def register_resolution_handler(resolution: Resolution, handler: Callable):
    """Зарегистрировать обработчик решения"""
    get_metrics_collector().register_resolution_handler(resolution, handler)


def get_dashboard() -> dict:
    """Получить дашборд ошибок"""
    return get_metrics_collector().get_dashboard()


def mark_error_resolved(error_index: int, notes: str = None):
    """Отметить ошибку как решённую"""
    get_metrics_collector().mark_error_resolved(error_index, notes)


def get_unresolved_tasks() -> List[Dict]:
    """Получить нерешённые задачи от клиентов"""
    return get_metrics_collector().get_unresolved_tasks()