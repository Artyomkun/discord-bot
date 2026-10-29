#!/usr/bin/env python3
"""
Протокол для обработки команд от gRPC клиента
"""

import logging
import time
from typing import Dict, Any, Optional

# Добавляем метрики
from .metrics import record_request, get_metrics_collector

logger = logging.getLogger(__name__)


class CommandProtocol:
    """Обработчик команд, приходящих через gRPC"""

    def __init__(self, bot):
        self.bot = bot
        self.metrics = get_metrics_collector()
        self._handlers = {
            'play': self._handle_play,
            'pause': self._handle_pause,
            'resume': self._handle_resume,
            'stop': self._handle_stop,
            'skip': self._handle_skip,
            'volume': self._handle_volume,
            'queue_status': self._handle_queue_status,
            'clear_queue': self._handle_clear_queue,
            'shuffle': self._handle_shuffle,
            'remove': self._handle_remove,
            'move': self._handle_move,
            'loop': self._handle_loop,
            'status': self._handle_status,
        }

    async def handle_command(self, command: str, user_id: str, guild_id: str, 
                             url: str = '', channel_id: str = '', 
                             options: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
        """
        Обработка команды
        
        Returns:
            Dict с результатом
        """
        start_time = time.time()
        handler = self._handlers.get(command)
        
        if not handler:
            logger.warning(f"Неизвестная команда: {command}")
            duration_ms = (time.time() - start_time) * 1000
            record_request(f'unknown_command_{command}', duration_ms, success=False, error='Unknown command')
            return {
                'success': False,
                'message': f'Unknown command: {command}',
                'data': {}
            }
        
        try:
            result = await handler(user_id, guild_id, url, channel_id, options or {})
            duration_ms = (time.time() - start_time) * 1000
            record_request(command, duration_ms, success=result.get('success', True))
            return result
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request(command, duration_ms, success=False, error=str(e))
            logger.error(f"Ошибка обработки команды {command}: {e}")
            return {
                'success': False,
                'message': str(e),
                'data': {}
            }

    async def _handle_play(self, user_id: str, guild_id: str, url: str, 
                           channel_id: str, options: Dict) -> Dict[str, Any]:
        """Обработка команды play"""
        start_time = time.time()
        try:
            guild = self.bot.get_guild(int(guild_id))
            if not guild:
                return {'success': False, 'message': 'Guild not found', 'data': {}}
            
            member = guild.get_member(int(user_id))
            if not member or not member.voice or not member.voice.channel:
                return {'success': False, 'message': 'You are not in a voice channel', 'data': {}}
            
            voice_channel = member.voice.channel
            
            if not voice_channel.permissions_for(guild.me).connect:
                return {'success': False, 'message': 'I don\'t have permission to connect', 'data': {}}
            
            # TODO: отправить в Java Gateway
            duration_ms = (time.time() - start_time) * 1000
            record_request('play_internal', duration_ms, success=True)
            return {'success': True, 'message': 'Playing', 'data': {'track': url}}
        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            record_request('play_internal', duration_ms, success=False, error=str(e))
            raise

    async def _handle_pause(self, user_id: str, guild_id: str, url: str, 
                            channel_id: str, options: Dict) -> Dict[str, Any]:
        """Приостановка воспроизведения"""
        start_time = time.time()
        duration_ms = (time.time() - start_time) * 1000
        record_request('pause', duration_ms, success=True)
        return {'success': True, 'message': 'Paused', 'data': {}}

    async def _handle_resume(self, user_id: str, guild_id: str, url: str, 
                             channel_id: str, options: Dict) -> Dict[str, Any]:
        """Возобновление воспроизведения"""
        start_time = time.time()
        duration_ms = (time.time() - start_time) * 1000
        record_request('resume', duration_ms, success=True)
        return {'success': True, 'message': 'Resumed', 'data': {}}

    async def _handle_stop(self, user_id: str, guild_id: str, url: str, 
                           channel_id: str, options: Dict) -> Dict[str, Any]:
        """Остановка воспроизведения"""
        start_time = time.time()
        duration_ms = (time.time() - start_time) * 1000
        record_request('stop', duration_ms, success=True)
        return {'success': True, 'message': 'Stopped', 'data': {}}

    async def _handle_skip(self, user_id: str, guild_id: str, url: str, 
                           channel_id: str, options: Dict) -> Dict[str, Any]:
        """Пропуск трека"""
        start_time = time.time()
        duration_ms = (time.time() - start_time) * 1000
        record_request('skip', duration_ms, success=True)
        return {'success': True, 'message': 'Skipped', 'data': {}}

    async def _handle_volume(self, user_id: str, guild_id: str, url: str, 
                             channel_id: str, options: Dict) -> Dict[str, Any]:
        """Изменение громкости"""
        start_time = time.time()
        level = options.get('level')
        if level:
            duration_ms = (time.time() - start_time) * 1000
            record_request('volume', duration_ms, success=True)
            return {'success': True, 'message': f'Volume set to {int(float(level) * 100)}%', 'data': {'volume': level}}
        duration_ms = (time.time() - start_time) * 1000
        record_request('volume', duration_ms, success=False, error='Volume level not provided')
        return {'success': False, 'message': 'Volume level not provided', 'data': {}}

    async def _handle_queue_status(self, user_id: str, guild_id: str, url: str, 
                                    channel_id: str, options: Dict) -> Dict[str, Any]:
        """Получение статуса очереди"""
        start_time = time.time()
        duration_ms = (time.time() - start_time) * 1000
        record_request('queue_status', duration_ms, success=True)
        return {
            'success': True, 
            'message': 'Queue status',
            'data': {
                'queue': {
                    'tracks': [],
                    'current_track': None
                }
            }
        }

    async def _handle_clear_queue(self, user_id: str, guild_id: str, url: str, 
                                   channel_id: str, options: Dict) -> Dict[str, Any]:
        """Очистка очереди"""
        start_time = time.time()
        duration_ms = (time.time() - start_time) * 1000
        record_request('clear_queue', duration_ms, success=True)
        return {'success': True, 'message': 'Queue cleared', 'data': {}}

    async def _handle_shuffle(self, user_id: str, guild_id: str, url: str, 
                              channel_id: str, options: Dict) -> Dict[str, Any]:
        """Перемешивание очереди"""
        start_time = time.time()
        duration_ms = (time.time() - start_time) * 1000
        record_request('shuffle', duration_ms, success=True)
        return {'success': True, 'message': 'Queue shuffled', 'data': {}}

    async def _handle_remove(self, user_id: str, guild_id: str, url: str, 
                             channel_id: str, options: Dict) -> Dict[str, Any]:
        """Удаление трека из очереди"""
        start_time = time.time()
        position = options.get('position')
        if position is not None:
            duration_ms = (time.time() - start_time) * 1000
            record_request('remove', duration_ms, success=True)
            return {'success': True, 'message': f'Track at position {position} removed', 'data': {'removed_track': {}}}
        duration_ms = (time.time() - start_time) * 1000
        record_request('remove', duration_ms, success=False, error='Position not provided')
        return {'success': False, 'message': 'Position not provided', 'data': {}}

    async def _handle_move(self, user_id: str, guild_id: str, url: str, 
                           channel_id: str, options: Dict) -> Dict[str, Any]:
        """Перемещение трека в очереди"""
        start_time = time.time()
        from_pos = options.get('from_position')
        to_pos = options.get('to_position')
        if from_pos is not None and to_pos is not None:
            duration_ms = (time.time() - start_time) * 1000
            record_request('move', duration_ms, success=True)
            return {'success': True, 'message': f'Track moved from {from_pos} to {to_pos}', 'data': {'moved_track': {}}}
        duration_ms = (time.time() - start_time) * 1000
        record_request('move', duration_ms, success=False, error='Positions not provided')
        return {'success': False, 'message': 'Positions not provided', 'data': {}}

    async def _handle_loop(self, user_id: str, guild_id: str, url: str, 
                           channel_id: str, options: Dict) -> Dict[str, Any]:
        """Управление зацикливанием"""
        start_time = time.time()
        mode = options.get('mode', 'off')
        mode_names = {'off': 'disabled', 'track': 'track', 'queue': 'queue'}
        duration_ms = (time.time() - start_time) * 1000
        record_request('loop', duration_ms, success=True)
        return {'success': True, 'message': f'Loop set to {mode_names.get(mode, mode)}', 'data': {}}

    async def _handle_status(self, user_id: str, guild_id: str, url: str, 
                             channel_id: str, options: Dict) -> Dict[str, Any]:
        """Получение статуса"""
        start_time = time.time()
        duration_ms = (time.time() - start_time) * 1000
        record_request('status', duration_ms, success=True)
        return {
            'success': True,
            'message': 'Status',
            'data': {
                'current_track': None,
                'position': 0,
                'duration': 0
            }
        }