# DSP Native Engine

Высокопроизводительный DSP-движок для обработки аудио на **Astra Linux (1.8.0, Debian-based)**  
с аппаратным ускорением через **ROCm 6.3.3** (AMD GPU) и **ZLUDA** (CUDA-совместимость на AMD).

Архитектура: Rust NIF (NIF для Elixir/Erlang) + C DSP + GPU backends.

---

## Системные требования

### Минимальные (пилот)
- **ОС:** Astra Linux 1.8+ (ядро 5.4+)
- **GPU:** AMD RX 6000+ / Instinct (gfx900/gfx906/gfx908/gfx90a/gfx1030/gfx1100)
- **RAM:** 16 ГБ
- **CPU:** 4 ядра
- **Диск:** 10 ГБ

### Драйверы и зависимости хоста
- `amdgpu` (встроен в ядро Astra)
- ROCm 6.3+ (`amdgpu-install --usecase=rocm`)
- Docker 24+ с пробросом `/dev/kfd`

### Проверка совместимости GPU
```bash
# На хосте (до запуска контейнера)
ls /dev/kfd                    # должен существовать
rocminfo | grep "Agent"        # должен видеть GPU
dmesg | grep -i amdgpu         # без ошибок
```

---

## Быстрый старт

### Сборка

```bash
cd music_core/audio_effects/native
docker compose --profile build build
```

> **Внимание:** Первая сборка занимает 1-2 часа из-за компиляции ROCm и ZLUDA из исходников.

### Запуск

```bash
docker compose --profile production up -d dsp-runtime
```

### Проверка

```bash
# Целостность артефактов
docker compose exec dsp-runtime sh -c "test -f /app/priv/native/libaudio_effects_native.so && echo '✅ Rust NIF ready'"
docker compose exec dsp-runtime sh -c "test -f /usr/local/lib/libdsp.so && echo '✅ C DSP ready'"

# GPU
docker compose exec dsp-runtime sh -c "ls /dev/kfd && echo '✅ /dev/kfd доступен'"
```

---

## Архитектура

```
┌─────────────────────────────────────────────────────────┐
│                    Elixir (BEAM)                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │       MusicCore.AudioEffects.Native.DSP          │   │
│  │           (Elixir NIF wrapper)                   │   │
│  └──────────────┬───────────────────────────────────┘   │
│                 │ NIF (Rustler)                         │
├─────────────────┼───────────────────────────────────────┤
│    Rust .so     ▼                                       │
│  libaudio_effects_native.so                             │
│  ┌────────────────────────────────────────────────┐    │
│  │  audio processing  │  backend dispatch          │    │
│  │  (CPU + GPU)       │  (auto-detect)             │    │
│  └────────┬───────────┴───────────────────────────┘    │
│           ▼ FFI                                         │
├─────────────────────────────────────────────────────────┤
│    C .so                                                │
│  libdsp.so (distortion, reverb, lpf, chorus)            │
│  ┌──────┬──────┬──────┬──────┐                          │
│  │ CUDA │ ROCk │ZLUDA │ CPU  │ ← GPU backends          │
│  └──────┴──────┴──────┴──────┘                          │
└─────────────────────────────────────────────────────────┘
```

### Этапы сборки (multi-stage)

| Stage | Базовый образ | Что собирает |
|-------|---------------|--------------|
| `c-builder` | Astra 1.8.0 | ROCm 6.3.3, ZLUDA (commit `6e2bd0ad`), libdsp.so |
| `rust-builder` | Astra 1.8.0 | libaudio_effects_native.so + dlopen-тест |
| `final` | Astra 1.8.0 | Только артефакты (~300 MB) |

---

## Профили docker-compose

| Профиль | Команда | Назначение |
|---------|---------|------------|
| `build` | `docker compose --profile build build` | Полная сборка |
| `production` | `docker compose --profile production up -d` | Запуск runtime |
| `ci` | `docker compose --profile ci run dsp-test` | Прогон тестов |

---

## Мониторинг в продакшене

### Метрики GPU (rocm-smi)
```bash
# Использование GPU
rocm-smi --showuse

# Температура
rocm-smi --showtemp

# Память
rocm-smi --showmeminfo
```

### Интеграция с Prometheus
Рекомендуется использовать [rocm-smi-exporter](https://github.com/ROCm/rocm-smi-exporter) или собирать метрики через `docker stats`.

### Логирование
- Логи приложения: `docker compose logs dsp-runtime`
- Логи сборки: `docker compose --profile build build --progress=plain`

### Метрики и пороги

| Метрика | Команда / источник | Порог |
|---------|--------------------|-------|
| Загрузка GPU | `rocm-smi --showuse` | < 90% |
| Температура GPU | `rocm-smi --showtemp` | < 85°C |
| Память GPU | `rocm-smi --showmeminfo` | < 90% |
| Загрузка CPU | `docker stats` | < 80% |
| Загрузка RAM | `docker stats` | < 80% |
| Частота падений | `docker compose logs \| grep crash \| wc -l` | < 1/час |

---

## Fallback и откат

### При отказе ZLUDA
Если ZLUDA не работает, DSP автоматически переключается на CPU-режим.
Для принудительного отключения GPU:
```bash
docker compose run -e ZLUDA_SUPPORT=0 dsp-runtime
```

### Откат версии образа
```bash
# Список версий
docker images | grep dsp-runtime

# Откат на предыдущую
docker compose down
export DSP_VERSION=1.0.0-rc1
docker compose --profile production up -d
```

---

## Сбор диагностики

При проблемах выполните:
```bash
./scripts/collect-diagnostics.sh
```

Скрипт собирает: логи контейнера, состояние GPU (rocm-smi, /dev/kfd, rocminfo), информацию об артефактах (.so), системную информацию (uname, память, CPU), результат healthcheck. Результат — `.tar.gz` архив.

---

## Совместимость с оркестраторами

### Kubernetes
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dsp-runtime
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: dsp-runtime
        image: dsp-native-runtime:1.0.0-rc1
        resources:
          limits:
            cpu: "4"
            memory: 8Gi
            nvidia.com/gpu: 1  # для GPU
          requests:
            cpu: "2"
            memory: 4Gi
        volumeMounts:
        - name: dev-kfd
          mountPath: /dev/kfd
      volumes:
      - name: dev-kfd
        hostPath:
          path: /dev/kfd
```

### Docker Swarm / Nomad
Аналогично — проброс `/dev/kfd` через device plugin.

---

## Поддержка и SLA

| Канал | Контакт | Время реакции |
|-------|---------|---------------|
| Telegram | @support_bot | 24/7, 1 час |
| Email | eng@company.ru | Рабочие дни, 4 часа |

### SLO (целевые)
- Доступность (healthcheck успешен): **99.5%**
- Время восстановления после падения: **< 15 минут**
- Время ответа на запрос: **< 100 мс (p95)**

---

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|-------------|----------|
| `ROCM_PATH` | `/opt/rocm` | Путь к ROCm |
| `AMDGPU_TARGETS` | `gfx900;...;gfx1100` | Целевые GPU |
| `HIP_PLATFORM` | `amd` | Платформа HIP |
| `ZLUDA_SUPPORT` | `1` | Включить ZLUDA |

---

## Ресурсы

- `/app/priv/native/libaudio_effects_native.so` — Rust NIF для Elixir
- `/usr/local/lib/libdsp.so` — C DSP библиотека
- `/opt/rocm/` — ROCm runtime
- `/opt/zluda/` — ZLUDA runtime