import Config

# Конфигурация для разработки
config :logger,
  level: :debug,
  truncate: :infinity

config :music_core, MusicCore.AudioEffects.Native.DSP,
  lib_path: Path.join(File.cwd!(), "priv/native/audio_effects_native")

config :music_core,
  audio_processing: [
    max_concurrent_streams: 5,
    debug: true,
    log_ffmpeg_output: false,
    use_real_audio: true,
    sample_rate: 48000,
    channels: 2,
    buffer_size: 4096
  ],

  effects: [
    debug: true,
    log_processing: false,
    realtime_preview: true
  ]

# Детальное логирование
config :music_core, MusicCore.AudioStream,
  log_level: :debug,
  log_errors: true,
  log_state_changes: true

# Используем локальный Redis
config :music_core, :redis,
  host: "localhost",
  port: 6379,
  pool_size: 10,
  socket_opts: []

# Реальные сервисы (без моков)
config :music_core, :services,
  go_processor: [
    host: "localhost",
    port: 8080,
    timeout: 10000,
    retries: 3,
    enabled: true
  ],

  java_gateway: [
    host: "localhost",
    port: 8081,
    timeout: 8000,
    retries: 3,
    enabled: true
  ]

# Реальный FFmpeg
config :music_core, MusicCore.AudioStreaming.FFmpeg,
  ffmpeg: [
    path: "ffmpeg",
    buffer_size: 8192,
    sample_rate: 48000,
    channels: 2,
    bitrate: 128,
    codec: "libopus",
    format: "opus",
    reconnect_attempts: 10,
    reconnect_delay: 1000,
    frame_buffer: 5000,
    opus_quality: 4,
    compression_level: 10,
    packet_loss: 0,
    application: "audio"
  ]

# Настройки WebSocket для реального трафика
config :music_core, MusicCore.WebSocketHandler,
  heartbeat_interval: 30000,
  max_frame_size: 65536

# Таймауты
config :music_core,
  request_timeout: 15000,  # 15 секунд для аудио
  connect_timeout: 5000,
  audio_timeout: 30000  # 30 секунд на обработку трека

# Отладка и профилирование
config :music_core,
  profile_audio_processing: true,
  log_memory_usage: false,
  log_cpu_usage: false

# Для hot code reload в dev
if Mix.env() == :dev do
  config :music_core,
    code_reloader: true

  # Отслеживаем изменения в папках
  config :music_core,
    watchers: [
      audio: {:file_system, [directories: ["audio_effects", "audio_streaming"]]}
    ]
end

# Отключаем ненужные проверки в dev
config :music_core, :security,
  rate_limiting: [enabled: false],
  request_validation: [enabled: false]

# Настройки пула процессов для аудио
config :music_core, MusicCore.AudioProcessor,
  pool_size: System.schedulers_online() * 2,
  max_queue: 100,
  shutdown: 15000
