import Config

# Конфигурация во время выполнения
if config_env() == :prod do
  # Секретные ключи для веб-сервера
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  signing_salt = System.get_env("SIGNING_SALT") || "default_signing_salt"
  encryption_salt = System.get_env("ENCRYPTION_SALT") || "default_encryption_salt"

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  # Веб-сервер
  config :music_core, MusicCore.Router,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0},
      port: port,
      protocol_options: [idle_timeout: 30_000]
    ],
    secret_key_base: secret_key_base,
    signing_salt: signing_salt,
    encryption_salt: encryption_salt,
    server: true,
    cache_static_manifest: "priv/static/cache_manifest.json"

  # База данных
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL environment variable is missing"

  config :music_core, MusicCore.Buffer,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true,
    parameters: [application_name: "music_core"]

  # Redis
  redis_host = System.get_env("REDIS_HOST") || "localhost"
  redis_port = String.to_integer(System.get_env("REDIS_PORT") || "6379")
  redis_password = System.get_env("REDIS_PASSWORD")

  config :music_core, :redis,
    host: redis_host,
    port: redis_port,
    password: redis_password,
    pool_size: String.to_integer(System.get_env("REDIS_POOL_SIZE") || "20")

  # FFmpeg
  ffmpeg_path = System.get_env("FFMPEG_PATH") || "ffmpeg"
  ffmpeg_buffer_size = String.to_integer(System.get_env("FFMPEG_BUFFER_SIZE") || "8192")
  ffmpeg_sample_rate = String.to_integer(System.get_env("FFMPEG_SAMPLE_RATE") || "48000")
  ffmpeg_channels = String.to_integer(System.get_env("FFMPEG_CHANNELS") || "2")
  ffmpeg_bitrate = String.to_integer(System.get_env("FFMPEG_BITRATE") || "128")
  ffmpeg_codec = System.get_env("FFMPEG_CODEC") || "libopus"
  ffmpeg_format = System.get_env("FFMPEG_FORMAT") || "opus"
  ffmpeg_reconnect_attempts = String.to_integer(System.get_env("FFMPEG_RECONNECT_ATTEMPTS") || "10")
  ffmpeg_reconnect_delay = String.to_integer(System.get_env("FFMPEG_RECONNECT_DELAY") || "1000")
  ffmpeg_frame_buffer = String.to_integer(System.get_env("FFMPEG_FRAME_BUFFER") || "5000")
  ffmpeg_opus_quality = String.to_integer(System.get_env("FFMPEG_OPUS_QUALITY") || "4")

  config :music_core, MusicCore.AudioStreaming.FFmpeg,
    ffmpeg: [
      path: ffmpeg_path,
      buffer_size: ffmpeg_buffer_size,
      sample_rate: ffmpeg_sample_rate,
      channels: ffmpeg_channels,
      bitrate: ffmpeg_bitrate,
      codec: ffmpeg_codec,
      format: ffmpeg_format,
      reconnect_attempts: ffmpeg_reconnect_attempts,
      reconnect_delay: ffmpeg_reconnect_delay,
      frame_buffer: ffmpeg_frame_buffer,
      opus_quality: ffmpeg_opus_quality
    ]
    
  # Go/Java сервисы
  config :music_core, :services,
    go_processor: [
      host: System.get_env("GO_PROCESSOR_HOST") || "go-processor",
      port: String.to_integer(System.get_env("GO_PROCESSOR_PORT") || "8080"),
      timeout: 20000
    ],

    java_gateway: [
      host: System.get_env("JAVA_GATEWAY_HOST") || "java-gateway",
      port: String.to_integer(System.get_env("JAVA_GATEWAY_PORT") || "8081"),
      timeout: 20000
    ]

  # Аудио-обработка
  config :music_core,
    audio_processing: [
      max_concurrent_streams: 100,
      temp_dir: System.get_env("TEMP_DIR") || "/tmp/music_core",
      cleanup_interval: 1800
    ]

  # Настройки для Docker/Kubernetes
  config :music_core, MusicCore.AudioProcessor,
    pool_size: String.to_integer(System.get_env("AUDIO_POOL_SIZE") || "50"),
    max_queue: 500

  # Безопасность
  config :music_core, :security,
    rate_limiting: [
      enabled: true,
      requests_per_minute: 60,
      burst_limit: 10
    ],
    cors: [
      origins: [System.get_env("CORS_ORIGIN") || "https://#{host}"],
      credentials: true,
      max_age: 86400
    ]
end
