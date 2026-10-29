#!/usr/bin/env python3
"""
Метрики для gRPC клиента с приёмом команд от сервера и отправкой нерешённых задач
"""

import time
import threading
import logging
import requests
from typing import Dict, List, Optional, Callable
from collections import deque
from dataclasses import dataclass, field
from enum import Enum

logger = logging.getLogger(__name__)


class AlertSeverity(Enum):
    """Уровень критичности алерта"""
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"


class ClientCommand(Enum):
    """Команды от сервера"""
    INCREASE_TIMEOUT = "increase_timeout"
    DECREASE_TIMEOUT = "decrease_timeout"
    RECONNECT = "reconnect"
    SHUTDOWN = "shutdown"
    RESET = "reset"
    INCREASE_RETRY = "increase_retry"
    DECREASE_RETRY = "decrease_retry"
    SWITCH_BACKEND = "switch_backend"
    REPORT_STATUS = "report_status"


@dataclass
class Alert:
    """Структура алерта"""
    severity: AlertSeverity
    message: str
    timestamp: float = field(default_factory=time.time)
    details: Optional[Dict] = None


@dataclass
class ServerCommand:
    """Команда от сервера"""
    command: ClientCommand
    params: Dict = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)
    source: str = "server"


@dataclass
class UnresolvedTask:
    """Неразрешённая задача для отправки на сервер"""
    task_id: str
    error_type: str
    error: str
    method: str
    client_id: str
    timestamp: float
    retry_count: int = 0
    last_attempt: float = field(default_factory=time.time)


@dataclass
class RequestMetrics:
    """Метрики одного запроса"""
    method: str
    start_time: float
    end_time: Optional[float] = None
    success: bool = True
    error: Optional[str] = None
    duration_ms: float = 0.0


class ClientMetricsCollector:
    """Сборщик метрик для клиента с алертами, приёмом команд и отправкой нерешённых задач"""

    def __init__(self, window_size: int = 1000, alert_handlers: List[Callable] = None,
                 server_metrics_url: str = None):
        self._lock = threading.Lock()
        self.window_size = window_size
        self.requests: deque = deque(maxlen=window_size)
        self.total_requests = 0
        self.successful_requests = 0
        self.failed_requests = 0
        self.start_time = time.time()
        self._method_stats: Dict[str, Dict] = {}
        self._connection_stats: Dict[str, Dict] = {}
        self._alerts: deque = deque(maxlen=100)
        self._alert_handlers = alert_handlers or []
        self._command_handlers: Dict[ClientCommand, List[Callable]] = {}
        self._server_commands: deque = deque(maxlen=100)
        self._unresolved_tasks: Dict[str, UnresolvedTask] = {}
        self._server_metrics_url = server_metrics_url or "http://localhost:50051/api/metrics"
        self._max_retries = 3
        self._retry_delay = 5  # seconds
        
        # Пороги для алертов
        self.thresholds = {
            'error_rate': 0.1,
            'high_latency_ms': 5000,
            'connection_failures': 5,
            'request_rate': 100,
            'max_timeout_ms': 30000,
            'min_timeout_ms': 1000,
            'current_timeout_ms': 5000,
            'retry_count': 3,
            'backend': 'primary',
            'critical_error_threshold': 3,  # 3 ошибки за 60 секунд
            'critical_error_window': 60,
        }
        
        # Запускаем фоновый поток для обработки нерешённых задач
        self._running = True
        self._start_processor_thread()

    def _start_processor_thread(self):
        """Запустить фоновый поток для обработки нерешённых задач"""
        import threading
        
        def processor_worker():
            while self._running:
                time.sleep(5)  # Проверяем каждые 5 секунд
                self._process_unresolved_tasks()
        
        thread = threading.Thread(target=processor_worker, daemon=True)
        thread.start()

    def _process_unresolved_tasks(self):
        """Обработать нерешённые задачи"""
        now = time.time()
        to_send = []
        
        with self._lock:
            for task_id, task in list(self._unresolved_tasks.items()):
                # Проверяем, нужно ли отправить задачу
                if now - task.last_attempt > self._retry_delay and task.retry_count < self._max_retries:
                    task.retry_count += 1
                    task.last_attempt = now
                    to_send.append(task)
                
                # Если превысили лимит, отправляем критическое уведомление
                if task.retry_count >= self._max_retries:
                    self._send_critical_alert(task)
                    del self._unresolved_tasks[task_id]
        
        # Отправляем задачи на сервер
        for task in to_send:
            self._send_to_server_metrics(task)

    def _send_to_server_metrics(self, task: UnresolvedTask):
        """Отправить нерешённую задачу в серверные метрики"""
        try:
            data = {
                'task_id': task.task_id,
                'error_type': task.error_type,
                'error': task.error,
                'method': task.method,
                'client_id': task.client_id,
                'timestamp': task.timestamp,
                'retry_count': task.retry_count,
                'source': 'client_metrics'
            }
            
            # Отправляем через HTTP или gRPC
            if self._server_metrics_url:
                response = requests.post(
                    f"{self._server_metrics_url}/api/unresolved_task",
                    json=data,
                    timeout=5
                )
                if response.status_code == 200:
                    logger.info(f"📤 Нерешённая задача {task.task_id} отправлена на сервер")
                else:
                    logger.warning(f"⚠️ Ошибка отправки задачи: {response.status_code}")
            else:
                # Логируем для отладки
                logger.warning(f"⚠️ Не удалось отправить задачу {task.task_id}: нет URL сервера")
                
        except Exception as e:
            logger.error(f"❌ Ошибка отправки нерешённой задачи: {e}")

    def _send_critical_alert(self, task: UnresolvedTask):
        """Отправить критическое уведомление о нерешённой задаче"""
        self._trigger_alert(
            AlertSeverity.CRITICAL,
            f"Unresolved task after {self._max_retries} retries: {task.error_type} - {task.method}",
            {
                'task_id': task.task_id,
                'error': task.error,
                'method': task.method,
                'client_id': task.client_id,
                'retries': task.retry_count
            }
        )

    def _add_unresolved_task(self, error: str, error_type: str, method: str, client_id: str = None):
        """Добавить нерешённую задачу"""
        task_id = f"{int(time.time())}_{method}_{hash(error)}"
        task = UnresolvedTask(
            task_id=task_id,
            error_type=error_type,
            error=error,
            method=method,
            client_id=client_id or "unknown",
            timestamp=time.time()
        )
        
        with self._lock:
            self._unresolved_tasks[task_id] = task
        
        logger.warning(f"📋 Добавлена нерешённая задача {task_id}: {error[:100]}")

    def _check_critical_errors(self):
        """Проверить критический уровень ошибок"""
        with self._lock:
            now = time.time()
            window_start = now - self.thresholds['critical_error_window']
            
            # Считаем ошибки в окне
            errors_in_window = sum(1 for r in self.requests 
                                    if not r['success'] and r['timestamp'] > window_start)
            
            if errors_in_window >= self.thresholds['critical_error_threshold']:
                self._trigger_alert(
                    AlertSeverity.CRITICAL,
                    f"Critical error rate detected: {errors_in_window} errors in {self.thresholds['critical_error_window']}s",
                    {'errors': errors_in_window, 'window': self.thresholds['critical_error_window']}
                )
                
                # Отправляем критическое уведомление на сервер
                self._send_critical_to_server(errors_in_window)

    def _send_critical_to_server(self, error_count: int):
        """Отправить критическое уведомление на сервер"""
        if self._server_metrics_url:
            try:
                data = {
                    'type': 'critical_error_rate',
                    'error_count': error_count,
                    'window_seconds': self.thresholds['critical_error_window'],
                    'timestamp': time.time(),
                    'source': 'client_metrics'
                }
                requests.post(
                    f"{self._server_metrics_url}/api/critical_alert",
                    json=data,
                    timeout=5
                )
            except Exception as e:
                logger.error(f"Ошибка отправки критического уведомления: {e}")

    # ========== Обработка команд от сервера ==========

    def register_command_handler(self, command: ClientCommand, handler: Callable):
        """Зарегистрировать обработчик команды"""
        if command not in self._command_handlers:
            self._command_handlers[command] = []
        self._command_handlers[command].append(handler)

    def receive_server_command(self, command_data: Dict):
        """Получить команду от сервера"""
        try:
            command = ClientCommand(command_data.get('command'))
            params = command_data.get('params', {})
            
            server_cmd = ServerCommand(
                command=command,
                params=params,
                source=command_data.get('source', 'server')
            )
            
            self._server_commands.append(server_cmd)
            
            logger.info(f"📡 Получена команда от сервера: {command.value} (params: {params})")
            
            # Вызываем обработчики
            if command in self._command_handlers:
                for handler in self._command_handlers[command]:
                    try:
                        handler(server_cmd)
                    except Exception as e:
                        logger.error(f"Ошибка в обработчике команды {command.value}: {e}")
            
            # Выполняем стандартные действия
            self._execute_command(server_cmd)
            
        except Exception as e:
            logger.error(f"Ошибка обработки команды от сервера: {e}")

    def _execute_command(self, cmd: ServerCommand):
        """Выполнить команду"""
        if cmd.command == ClientCommand.INCREASE_TIMEOUT:
            new_timeout = min(
                self.thresholds['current_timeout_ms'] * 1.5,
                self.thresholds['max_timeout_ms']
            )
            self.thresholds['current_timeout_ms'] = new_timeout
            logger.info(f"⏱️ Таймаут увеличен до {new_timeout}ms")
            
        elif cmd.command == ClientCommand.DECREASE_TIMEOUT:
            new_timeout = max(
                self.thresholds['current_timeout_ms'] * 0.8,
                self.thresholds['min_timeout_ms']
            )
            self.thresholds['current_timeout_ms'] = new_timeout
            logger.info(f"⏱️ Таймаут уменьшен до {new_timeout}ms")
            
        elif cmd.command == ClientCommand.RECONNECT:
            logger.info("🔄 Получена команда переподключения")
            
        elif cmd.command == ClientCommand.SHUTDOWN:
            logger.warning("⚠️ Получена команда завершения работы")
            
        elif cmd.command == ClientCommand.RESET:
            logger.info("🔄 Получена команда сброса")
            self.reset()
            
        elif cmd.command == ClientCommand.INCREASE_RETRY:
            new_retry = min(self.thresholds['retry_count'] + 1, 10)
            self.thresholds['retry_count'] = new_retry
            logger.info(f"🔄 Количество повторных попыток увеличено до {new_retry}")
            
        elif cmd.command == ClientCommand.DECREASE_RETRY:
            new_retry = max(self.thresholds['retry_count'] - 1, 1)
            self.thresholds['retry_count'] = new_retry
            logger.info(f"🔄 Количество повторных попыток уменьшено до {new_retry}")
            
        elif cmd.command == ClientCommand.SWITCH_BACKEND:
            new_backend = cmd.params.get('backend', 'fallback')
            old_backend = self.thresholds['backend']
            self.thresholds['backend'] = new_backend
            logger.info(f"🔄 Переключение бэкенда: {old_backend} -> {new_backend}")
            
        elif cmd.command == ClientCommand.REPORT_STATUS:
            logger.info("📊 Получен запрос статуса")

    # ========== Существующие методы ==========

    def _check_alerts(self):
        """Проверить условия для алертов"""
        stats = self.get_stats()
        
        if stats['error_rate'] > self.thresholds['error_rate']:
            self._trigger_alert(
                AlertSeverity.ERROR,
                f"High error rate: {stats['error_rate']*100:.1f}%",
                {'error_rate': stats['error_rate'], 'total_requests': stats['total_requests']}
            )
        
        if stats['avg_response_time_ms'] > self.thresholds['high_latency_ms']:
            self._trigger_alert(
                AlertSeverity.WARNING,
                f"High latency: {stats['avg_response_time_ms']:.0f}ms",
                {'avg_response_time_ms': stats['avg_response_time_ms']}
            )
        
        if stats['requests_per_second'] > self.thresholds['request_rate']:
            self._trigger_alert(
                AlertSeverity.INFO,
                f"High request rate: {stats['requests_per_second']:.1f} RPS",
                {'rps': stats['requests_per_second']}
            )
        
        for conn in stats['connections']:
            if conn['error_rate'] > 0.3:
                self._trigger_alert(
                    AlertSeverity.WARNING,
                    f"High error rate on connection {conn['connection_id']}: {conn['error_rate']*100:.1f}%",
                    {'connection_id': conn['connection_id'], 'error_rate': conn['error_rate']}
                )
        
        # Проверяем критический уровень ошибок
        self._check_critical_errors()

    def _trigger_alert(self, severity: AlertSeverity, message: str, details: Dict = None):
        """Создать алерт и вызвать обработчики"""
        alert = Alert(severity=severity, message=message, details=details)
        self._alerts.append(alert)
        
        log_func = {
            AlertSeverity.INFO: logger.info,
            AlertSeverity.WARNING: logger.warning,
            AlertSeverity.ERROR: logger.error,
            AlertSeverity.CRITICAL: logger.critical
        }.get(severity, logger.warning)
        
        log_func(f"🔔 ALERT [{severity.value}]: {message}")
        
        for handler in self._alert_handlers:
            try:
                handler(alert)
            except Exception as e:
                logger.error(f"Alert handler error: {e}")

    def record_request(self, method: str, duration_ms: float, success: bool = True, error: str = None):
        """Записать метрики запроса"""
        with self._lock:
            self.total_requests += 1
            if success:
                self.successful_requests += 1
            else:
                self.failed_requests += 1
                
                # Если ошибка критическая, добавляем в нерешённые задачи
                if error and self._is_critical_error(error):
                    self._add_unresolved_task(error, "critical", method, None)
                
                if error and ("connection" in error.lower() or "timeout" in error.lower()):
                    self._trigger_alert(
                        AlertSeverity.ERROR,
                        f"Request failed: {method} - {error}",
                        {'method': method, 'error': error, 'duration_ms': duration_ms}
                    )

            self.requests.append({
                'method': method,
                'duration_ms': duration_ms,
                'success': success,
                'error': error,
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
                    'alerts': 0
                }

            stats = self._method_stats[method]
            stats['total'] += 1
            if success:
                stats['success'] += 1
            else:
                stats['failed'] += 1
                stats['alerts'] += 1
            stats['total_duration'] += duration_ms
            stats['min_duration'] = min(stats['min_duration'], duration_ms)
            stats['max_duration'] = max(stats['max_duration'], duration_ms)

            self._check_alerts()

    def _is_critical_error(self, error: str) -> bool:
        """Определить, является ли ошибка критической"""
        error_lower = error.lower()
        critical_patterns = [
            'memory', 'out of memory', 'oom',
            'connection refused', 'connection reset',
            'timeout', 'deadline exceeded',
            'unavailable', 'internal error',
            'database', 'crash', 'fatal'
        ]
        return any(pattern in error_lower for pattern in critical_patterns)

    def record_connection_event(self, event_type: str, connection_id: int, duration_ms: float, success: bool = True):
        """Записать событие соединения"""
        with self._lock:
            key = f"{connection_id}"
            if key not in self._connection_stats:
                self._connection_stats[key] = {
                    'connection_id': connection_id,
                    'events': {},
                    'total_events': 0,
                    'failed_events': 0,
                    'alerts': 0
                }
            
            conn_stats = self._connection_stats[key]
            if event_type not in conn_stats['events']:
                conn_stats['events'][event_type] = {
                    'total': 0,
                    'failed': 0,
                    'total_duration': 0,
                    'alerts': 0
                }
            
            event_stats = conn_stats['events'][event_type]
            event_stats['total'] += 1
            if not success:
                event_stats['failed'] += 1
                conn_stats['failed_events'] += 1
                event_stats['alerts'] += 1
                conn_stats['alerts'] += 1
                
                if event_type in ['create', 'get', 'close']:
                    self._trigger_alert(
                        AlertSeverity.WARNING,
                        f"Connection {event_type} failed: connection {connection_id}",
                        {'connection_id': connection_id, 'event_type': event_type, 'duration_ms': duration_ms}
                    )
                
                if conn_stats['failed_events'] > self.thresholds['connection_failures']:
                    self._trigger_alert(
                        AlertSeverity.CRITICAL,
                        f"Multiple connection failures: {conn_stats['failed_events']}",
                        {'connection_id': connection_id, 'failures': conn_stats['failed_events']}
                    )
                    
                    # Добавляем в нерешённые задачи
                    self._add_unresolved_task(
                        f"Connection {event_type} failed: {connection_id}",
                        "connection", event_type, str(connection_id)
                    )
            
            event_stats['total_duration'] += duration_ms
            conn_stats['total_events'] += 1

    def record_external_error(self, client_id: str, error: str, method: str = None):
        """Записать внешнюю ошибку от сервера"""
        with self._lock:
            self._trigger_alert(
                AlertSeverity.ERROR,
                f"External error from server: {error}",
                {'client_id': client_id, 'method': method, 'error': error}
            )
            
            # Добавляем в нерешённые задачи
            if self._is_critical_error(error):
                self._add_unresolved_task(error, "external", method or "unknown", client_id)

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
                'success_rate': self.successful_requests / self.total_requests if self.total_requests > 0 else 0,
                'requests_per_second': rps,
                'avg_response_time_ms': avg_recent_duration,
                'total_alerts': len(self._alerts),
                'current_timeout_ms': self.thresholds['current_timeout_ms'],
                'retry_count': self.thresholds['retry_count'],
                'backend': self.thresholds['backend'],
                'unresolved_tasks': len(self._unresolved_tasks),
                'methods': {},
                'alerts': [{'severity': a.severity.value, 'message': a.message, 'timestamp': a.timestamp} for a in self._alerts],
                'server_commands': [{'command': c.command.value, 'params': c.params, 'timestamp': c.timestamp} for c in self._server_commands]
            }

            for method, s in self._method_stats.items():
                stats['methods'][method] = {
                    'total': s['total'],
                    'success': s['success'],
                    'failed': s['failed'],
                    'alerts': s.get('alerts', 0),
                    'avg_duration_ms': s['total_duration'] / s['total'] if s['total'] > 0 else 0,
                    'min_duration_ms': s['min_duration'] if s['min_duration'] != float('inf') else 0,
                    'max_duration_ms': s['max_duration']
                }

            stats['connections'] = []
            for conn_id, s in self._connection_stats.items():
                stats['connections'].append({
                    'connection_id': s['connection_id'],
                    'total_events': s['total_events'],
                    'failed_events': s['failed_events'],
                    'alerts': s.get('alerts', 0),
                    'error_rate': s['failed_events'] / s['total_events'] if s['total_events'] > 0 else 0,
                    'events': {
                        event_type: {
                            'total': e['total'],
                            'failed': e['failed'],
                            'alerts': e.get('alerts', 0),
                            'error_rate': e['failed'] / e['total'] if e['total'] > 0 else 0,
                            'avg_duration_ms': e['total_duration'] / e['total'] if e['total'] > 0 else 0
                        }
                        for event_type, e in s['events'].items()
                    }
                })

            return stats

    def get_alerts(self) -> List[Alert]:
        """Получить все алерты"""
        with self._lock:
            return list(self._alerts)

    def get_commands(self) -> List[ServerCommand]:
        """Получить полученные команды"""
        with self._lock:
            return list(self._server_commands)

    def get_unresolved_tasks(self) -> List[UnresolvedTask]:
        """Получить нерешённые задачи"""
        with self._lock:
            return list(self._unresolved_tasks.values())

    def clear_alerts(self):
        """Очистить алерты"""
        with self._lock:
            self._alerts.clear()

    def clear_commands(self):
        """Очистить историю команд"""
        with self._lock:
            self._server_commands.clear()

    def clear_unresolved_tasks(self):
        """Очистить нерешённые задачи"""
        with self._lock:
            self._unresolved_tasks.clear()

    def reset(self):
        """Сбросить метрики"""
        with self._lock:
            self.requests.clear()
            self.total_requests = 0
            self.successful_requests = 0
            self.failed_requests = 0
            self.start_time = time.time()
            self._method_stats.clear()
            self._connection_stats.clear()
            self._alerts.clear()
            self._unresolved_tasks.clear()

    def set_threshold(self, name: str, value: float):
        """Установить порог для алерта"""
        if name in self.thresholds:
            self.thresholds[name] = value
            logger.info(f"Alert threshold {name} set to {value}")

    def shutdown(self):
        """Остановить сборщик метрик"""
        self._running = False


class ClientMetricsExporter:
    """Экспорт метрик клиента"""

    def __init__(self, collector: ClientMetricsCollector):
        self.collector = collector

    def to_prometheus(self) -> str:
        """Экспорт в формате Prometheus"""
        stats = self.collector.get_stats()
        lines = []

        lines.append(f"# HELP grpc_client_total_requests Total gRPC requests")
        lines.append(f"# TYPE grpc_client_total_requests counter")
        lines.append(f"grpc_client_total_requests {stats['total_requests']}")

        lines.append(f"# HELP grpc_client_successful_requests Successful requests")
        lines.append(f"# TYPE grpc_client_successful_requests counter")
        lines.append(f"grpc_client_successful_requests {stats['successful_requests']}")

        lines.append(f"# HELP grpc_client_failed_requests Failed requests")
        lines.append(f"# TYPE grpc_client_failed_requests counter")
        lines.append(f"grpc_client_failed_requests {stats['failed_requests']}")

        lines.append(f"# HELP grpc_client_alerts_total Total alerts")
        lines.append(f"# TYPE grpc_client_alerts_total counter")
        lines.append(f"grpc_client_alerts_total {stats['total_alerts']}")

        lines.append(f"# HELP grpc_client_unresolved_tasks Unresolved tasks")
        lines.append(f"# TYPE grpc_client_unresolved_tasks gauge")
        lines.append(f"grpc_client_unresolved_tasks {stats['unresolved_tasks']}")

        lines.append(f"# HELP grpc_client_success_rate Success rate")
        lines.append(f"# TYPE grpc_client_success_rate gauge")
        lines.append(f"grpc_client_success_rate {stats['success_rate']}")

        lines.append(f"# HELP grpc_client_rps Requests per second")
        lines.append(f"# TYPE grpc_client_rps gauge")
        lines.append(f"grpc_client_rps {stats['requests_per_second']}")

        lines.append(f"# HELP grpc_client_avg_response_time_ms Average response time")
        lines.append(f"# TYPE grpc_client_avg_response_time_ms gauge")
        lines.append(f"grpc_client_avg_response_time_ms {stats['avg_response_time_ms']}")

        lines.append(f"# HELP grpc_client_current_timeout_ms Current timeout in ms")
        lines.append(f"# TYPE grpc_client_current_timeout_ms gauge")
        lines.append(f"grpc_client_current_timeout_ms {stats['current_timeout_ms']}")

        lines.append(f"# HELP grpc_client_retry_count Current retry count")
        lines.append(f"# TYPE grpc_client_retry_count gauge")
        lines.append(f"grpc_client_retry_count {stats['retry_count']}")

        for method, s in stats['methods'].items():
            method_clean = method.replace('.', '_')
            lines.append(f"# HELP grpc_client_method_{method_clean}_total Total requests for {method}")
            lines.append(f"# TYPE grpc_client_method_{method_clean}_total counter")
            lines.append(f"grpc_client_method_{method_clean}_total {s['total']}")

            lines.append(f"# HELP grpc_client_method_{method_clean}_alerts Alerts for {method}")
            lines.append(f"# TYPE grpc_client_method_{method_clean}_alerts counter")
            lines.append(f"grpc_client_method_{method_clean}_alerts {s.get('alerts', 0)}")

            lines.append(f"# HELP grpc_client_method_{method_clean}_avg_duration_ms Average duration for {method}")
            lines.append(f"# TYPE grpc_client_method_{method_clean}_avg_duration_ms gauge")
            lines.append(f"grpc_client_method_{method_clean}_avg_duration_ms {s['avg_duration_ms']}")

        return '\n'.join(lines)

    def to_json(self) -> dict:
        """Экспорт в JSON"""
        return self.collector.get_stats()

    def to_text(self) -> str:
        """Экспорт в читаемый текст"""
        stats = self.collector.get_stats()
        lines = [
            "=" * 50,
            "gRPC Client Metrics",
            "=" * 50,
            f"Uptime: {stats['uptime_seconds']:.0f} seconds",
            f"Total requests: {stats['total_requests']}",
            f"Successful: {stats['successful_requests']}",
            f"Failed: {stats['failed_requests']}",
            f"Alerts: {stats['total_alerts']}",
            f"Unresolved tasks: {stats['unresolved_tasks']}",
            f"Success rate: {stats['success_rate']*100:.1f}%",
            f"RPS: {stats['requests_per_second']:.2f}",
            f"Avg response time: {stats['avg_response_time_ms']:.2f} ms",
            f"Current timeout: {stats['current_timeout_ms']} ms",
            f"Retry count: {stats['retry_count']}",
            f"Backend: {stats['backend']}",
            "",
            "Methods:"
        ]

        for method, s in stats['methods'].items():
            lines.append(f"  {method}:")
            lines.append(f"    total: {s['total']}")
            lines.append(f"    alerts: {s.get('alerts', 0)}")
            lines.append(f"    avg: {s['avg_duration_ms']:.2f} ms")
            lines.append(f"    min: {s['min_duration_ms']:.2f} ms")
            lines.append(f"    max: {s['max_duration_ms']:.2f} ms")

        if stats['connections']:
            lines.append("")
            lines.append("Connections:")
            for conn in stats['connections']:
                lines.append(f"  Connection {conn['connection_id']}:")
                lines.append(f"    events: {conn['total_events']}")
                lines.append(f"    errors: {conn['failed_events']}")
                lines.append(f"    alerts: {conn.get('alerts', 0)}")
                lines.append(f"    error rate: {conn['error_rate']*100:.1f}%")
                for event_type, e in conn['events'].items():
                    lines.append(f"      {event_type}:")
                    lines.append(f"        total: {e['total']}")
                    lines.append(f"        alerts: {e.get('alerts', 0)}")
                    lines.append(f"        avg duration: {e['avg_duration_ms']:.2f} ms")

        if stats.get('alerts'):
            lines.append("")
            lines.append("Recent alerts:")
            for alert in stats['alerts'][-10:]:
                lines.append(f"  [{alert['severity']}] {alert['message']}")

        if stats.get('server_commands'):
            lines.append("")
            lines.append("Server commands:")
            for cmd in stats['server_commands'][-10:]:
                lines.append(f"  {cmd['command']}: {cmd['params']}")

        return '\n'.join(lines)


# Глобальный сборщик
_metrics_collector = None


def get_metrics_collector(server_metrics_url: str = None) -> ClientMetricsCollector:
    """Получить глобальный сборщик метрик"""
    global _metrics_collector
    if _metrics_collector is None:
        _metrics_collector = ClientMetricsCollector(server_metrics_url=server_metrics_url)
    return _metrics_collector


def record_request(method: str, duration_ms: float, success: bool = True, error: str = None):
    """Удобная функция для записи метрик"""
    get_metrics_collector().record_request(method, duration_ms, success, error)


def record_connection_event(event_type: str, connection_id: int, duration_ms: float, success: bool = True):
    """Записать событие соединения"""
    get_metrics_collector().record_connection_event(event_type, connection_id, duration_ms, success)


def add_alert_handler(handler: Callable):
    """Добавить обработчик алертов"""
    get_metrics_collector()._alert_handlers.append(handler)


def set_threshold(name: str, value: float):
    """Установить порог алерта"""
    get_metrics_collector().set_threshold(name, value)


def receive_server_command(command_data: Dict):
    """Получить команду от сервера"""
    get_metrics_collector().receive_server_command(command_data)


def register_command_handler(command: ClientCommand, handler: Callable):
    """Зарегистрировать обработчик команды"""
    get_metrics_collector().register_command_handler(command, handler)


def get_unresolved_tasks() -> List[UnresolvedTask]:
    """Получить нерешённые задачи"""
    return get_metrics_collector().get_unresolved_tasks()


def clear_unresolved_tasks():
    """Очистить нерешённые задачи"""
    get_metrics_collector().clear_unresolved_tasks()


def shutdown():
    """Остановить сборщик метрик"""
    if _metrics_collector:
        _metrics_collector.shutdown()