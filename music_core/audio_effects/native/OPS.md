# OPS — Эксплуатация DSP Native Engine

## Команды

### Сборка
```bash
# Полная сборка (ROCm + ZLUDA + .so)
docker compose --profile build build

# Быстрая пересборка только Rust
docker compose build dsp-runtime
```

### Запуск
```bash
# Продакшен
docker compose --profile production up -d

# С логами
docker compose --profile production up -d && docker compose logs -f
```

### Мониторинг
```bash
# Healthcheck (curl на порт 4000, если сервер запущен)
curl http://localhost:4000/health

# Проверка артефактов
docker compose exec dsp-runtime ls -la /app/priv/native/
docker compose exec dsp-runtime ls -la /usr/local/lib/libdsp.so

# GPU
docker compose exec dsp-runtime ls /dev/kfd
docker compose exec dsp-runtime cat /sys/class/kfd/kfd/topology/nodes/0/gpu_id
```

### Логи
```bash
# Все логи
docker compose logs dsp-runtime

# Только ошибки
docker compose logs dsp-runtime | grep -i error

# Последние N строк
docker compose logs --tail=100 -f dsp-runtime
```

---

## Диагностика падений

### Признак: ZLUDA упал
```bash
# Проверить, что GPU доступен
docker compose exec dsp-runtime ls -la /dev/kfd
# Если /dev/kfd отсутствует — контейнер не видит GPU
# Решение: docker compose down && docker compose up -d

# Проверить логи ZLUDA
docker compose logs dsp-runtime | grep -i zluda

# Fallback: остановить контейнер, проверить гостевую ОС
ls -la /dev/kfd   # должен существовать
sudo dmesg | grep -i kfd
```

### Признак: libaudio_effects_native.so не загружается
```bash
# Проверить наличие .so
docker compose exec dsp-runtime test -f /app/priv/native/libaudio_effects_native.so && echo OK

# Решение: пересобрать образ
docker compose --profile build build
```

### Признак: контейнер не стартует (OOM)
```bash
# Проверить логи
docker compose logs dsp-runtime | tail -50

# Увеличить лимиты в docker-compose.yml:
#   deploy.resources.limits.memory: 16G
#   deploy.resources.limits.cpus: '8'

# Проверить память
docker stats dsp-runtime
```

---

## Fallback-план

| Сценарий | Действие |
|----------|----------|
| ZLUDA не работает | Перезапустить контейнер. Если не помогло — собрать логи и отправить разработчикам. GUI-обработка переключается на CPU автоматически. |
| ROCm не собран | Временно использовать CPU-only Dockerfile: `docker compose build --build-arg CUDA_SUPPORT=0 ROCK_SUPPORT=0` |
| Полный отказ | Перезапустить ноду / контейнер. Собрать логи: `docker compose logs > crash-$(date +%Y%m%d-%H%M%S).log` |

---

## Graceful Shutdown

Контейнер принимает SIGTERM и завершается за 5 секунд (STOPSIGNAL SIGTERM).

Если нужно принудительно завершить:
```bash
docker compose kill -s SIGTERM dsp-runtime
# Через 10 секунд, если не завершился:
docker compose kill -s SIGKILL dsp-runtime