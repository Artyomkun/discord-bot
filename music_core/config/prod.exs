import Config

config :music_core, MusicCore.AudioEffects.Native.DSP,
  lib_path: Path.join(File.cwd!(), "priv/native/audio_effects_native")

config :music_core, MusicCore.WebSocket.Endpoint,
  https: [port: 8443]

# Конфигурация для production
config :logger,
  level: :info

# Production настройки аудио
config :music_core,
  audio_processing: [
    max_concurrent_streams: 50,
    temp_dir: "/tmp/music_core",
    cleanup_interval: 3600,
    sample_rate: 48000,
    channels: 2,
    buffer_size: 8192,
    max_file_size_mb: 100
  ]

# Redis
config :music_core, :redis,
  host: System.get_env("REDIS_HOST") || "localhost",
  port: System.get_env("REDIS_PORT") || 6379,
  password: System.get_env("REDIS_PASSWORD"),
  pool_size: String.to_integer(System.get_env("REDIS_POOL_SIZE") || "20")

# FFmpeg production
config :music_core, MusicCore.AudioStreaming.FFmpeg,
  ffmpeg: [
    path: System.get_env("FFMPEG_PATH") || "ffmpeg",
    buffer_size: String.to_integer(System.get_env("FFMPEG_BUFFER_SIZE") || "4096"),
    sample_rate: String.to_integer(System.get_env("FFMPEG_SAMPLE_RATE") || "48000"),
    channels: String.to_integer(System.get_env("FFMPEG_CHANNELS") || "2"),
    bitrate: String.to_integer(System.get_env("FFMPEG_BITRATE") || "128"),
    codec: System.get_env("FFMPEG_CODEC") || "libmp3lame",
    format: System.get_env("FFMPEG_FORMAT") || "mp3",
    reconnect_attempts: String.to_integer(System.get_env("FFMPEG_RECONNECT_ATTEMPTS") || "20"),
    reconnect_delay: String.to_integer(System.get_env("FFMPEG_RECONNECT_DELAY") || "1000"),
    threads: String.to_integer(System.get_env("FFMPEG_THREADS") || "2"),
    loglevel: System.get_env("FFMPEG_LOGLEVEL") || "error"
  ]

# Go/Java сервисы
config :music_core, :services,
  go_processor: [
    host: System.get_env("GO_PROCESSOR_HOST") || "localhost",
    port: String.to_integer(System.get_env("GO_PROCESSOR_PORT") || "8080"),
    timeout: 15000
  ],

  java_gateway: [
    host: System.get_env("JAVA_GATEWAY_HOST") || "localhost",
    port: String.to_integer(System.get_env("JAVA_GATEWAY_PORT") || "8081"),
    timeout: 15000
  ]

# Мониторинг
config :music_core, :telemetry,
  metrics: [
    {:counter, "music_core.audio.processed"},
    {:distribution, "music_core.audio.processing_time_ms"},
    {:last_value, "music_core.streams.active"},
    {:sum, "music_core.errors.total"}
  ]

# Таймауты
config :music_core,
  request_timeout: 30000,
  audio_processing_timeout: 60000,
  connect_timeout: 10000

# Пул процессов
config :music_core, MusicCore.AudioProcessor,
  pool_size: String.to_integer(System.get_env("AUDIO_POOL_SIZE") || "40"),
  max_queue: 200,
  shutdown: 30000
