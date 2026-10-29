# Discord Music Bot - Elixir Music Bot

Многоязычный музыкальный бот для Discord с распределенной архитектурой.

## Архитектура

Бот состоит из нескольких сервисов, взаимодействующих между собой:

- **Python Discord Bot** - основной бот для Discord (порт 5000)
- **Java Gateway** - маршрутизатор команд (порт 8080)
- **Go Audio Processor** - обработка аудио (порт 8081)
- **Elixir Phoenix** - стриминг и эффекты (порт 4000)

## Структура проекта

```text
elixir_music_bot/
├── music_core/
│   └── go_processor/
│       ├── main.go                    # Go сервис
│       ├── internal/
│       │   ├── audio/processor.go     # Аудио обработка
│       │   └── bridge/                # Мосты к другим сервисам
│       └── java_gateway/
│           ├── python_client/         # Python Discord бот
│           │   ├── bot.py
│           │   ├── commands/
│           │   └── utils/
│           └── src/main/java/com/bot/ # Java Gateway
├── test_services.py                   # Тестовый скрипт
└── README.md
```

## Запуск

### 1. Go Audio Processor

```bash
cd elixir_music_bot/music_core/go_processor
go mod tidy
go run main.go
```

Сервис запустится на <http://localhost:8081>

### 2. Java Gateway

```bash
cd elixir_music_bot/music_core/go_processor/java_gateway
mvn spring-boot:run
```

Сервис запустится на <http://localhost:8080>

### 3. Python Discord Bot

```bash
cd elixir_music_bot/music_core/go_processor/java_gateway/python_client
pip install -r requirements.txt

# Создайте .env файл с DISCORD_TOKEN
echo "DISCORD_TOKEN=your_discord_bot_token_here" > .env

python bot.py
```

API сервер запустится на <http://localhost:5000>

### 4. Elixir Phoenix (опционально)

```bash
# Если есть Elixir сервис
mix phx.server
```

## Переменные окружения

Создайте `.env` файл в директории Python бота:

```env
DISCORD_TOKEN=your_discord_bot_token_here
JAVA_GATEWAY_URL=http://localhost:8080
PYTHON_API_PORT=5000
```

## Команды Discord бота

### Музыка

- `/play <url>` - воспроизвести музыку
- `/pause` - приостановить
- `/resume` - возобновить
- `/stop` - остановить и очистить очередь
- `/volume <0-100>` - изменить громкость

### Очередь

- `/queue` - показать очередь
- `/skip` - пропустить трек
- `/clear` - очистить очередь
- `/shuffle` - перемешать очередь
- `/remove <position>` - удалить трек
- `/move <from> <to>` - переместить трек

### Эффекты

- `/effects <effect> <intensity>` - применить эффект
- `/nowplaying` - текущий трек

## Эффекты аудио

Поддерживаемые эффекты:

- `echo` - эхо
- `reverb` - реверберация
- `chorus` - хорус
- `flanger` - флэнджер
- `phaser` - фэйзер
- `distortion` - дисторшн
- `equalizer` - эквалайзер

## Тестирование

Запустите тестовый скрипт для проверки всех сервисов:

```bash
cd elixir_music_bot
python test_services.py
```

## API Endpoints

### Java Gateway (8080)

- `GET /api/health` - health check
- `POST /api/process` - обработка аудио
- `POST /api/command` - команды от Python бота
- `POST /api/register/python` - регистрация Python бота
- `GET /api/python/status` - статус Python бота

### Go Processor (8081)

- `GET /health` - health check
- `POST /api/audio/process` - обработка аудио
- `GET /stats` - статистика

### Python Bot (5000)

- `GET /health` - health check
- `POST /api/command` - прием команд от Java
- `GET /status` - статус бота

## Разработка

### Добавление новых эффектов

1. Обновите структуру `AudioEffects` в `processor.go`
2. Добавьте логику применения в `ApplyEffects()`
3. Обновите команды в Python боте

### Добавление новых команд

1. Создайте новый cog в `commands/`
2. Зарегистрируйте в `bot.py`
3. Добавьте маршрутизацию в `RouterService.java`

## Логирование

Логи пишутся в:

- `bot.log` - Python бот
- Консоль - все сервисы

## Troubleshooting

### Сервис не запускается

1. Проверьте порты - убедитесь, что они свободны
2. Проверьте зависимости (Go modules, Maven, pip)
3. Проверьте переменные окружения

### Бот не подключается к Discord

1. Проверьте `DISCORD_TOKEN` в `.env`
2. Убедитесь, что токен действительный
3. Проверьте разрешения бота в Discord

### Команды не работают

1. Запустите `test_services.py` для диагностики
2. Проверьте логи каждого сервиса
3. Убедитесь, что все сервисы запущены

## Лицензия

MIT License
