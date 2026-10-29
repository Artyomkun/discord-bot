import Config

config :music_core, MusicCore.AudioEffects.Native.DSP,
  lib_path: Path.join(File.cwd!(), "priv/native/audio_effects_native")

# Общая конфигурация
config :music_core,
  env: Mix.env(),
  version: "0.1.0",

  audio_processing: [
    max_concurrent_streams: 10,
    max_queue_size: 100,
    default_bitrate: 128,
    supported_formats: ["mp3", "wav", "flac", "opus", "m4a", "ogg"],
    temp_dir: System.tmp_dir!() <> "/music_core"
  ],

  effects: [
    enabled: true,
    default_preset: :balanced,
    presets: %{
      flat: %{equalizer: %{}, compressor: %{threshold: -20, ratio: 2}},
      bass_boost: %{equalizer: %{"60" => 6.0, "230" => 3.0, "910" => -3.0}},
      vocal_boost: %{equalizer: %{"1000" => 3.0, "3000" => 2.0, "5000" => 1.0}},
      loud: %{compressor: %{threshold: -10, ratio: 4}}
    }
  ]

config :music_core, MusicCore.WebSocket.Endpoint,
  port: 4000

config :music_core, MusicCore.Repo,
  database: "music_core",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5432,
  pool_size: 10

# Конфигурация логгера
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :guild_id]

config :logger,
  level: :info

# Конфигурация Elixir
config :elixir,
  time_zone_database: Tzdata.TimeZoneDatabase,
  ansi_enabled: true

# Конфигурация аудио эффектов
config :music_core, MusicCore.AudioEffects,
  normalizer: [
    target_lufs: -16,
    max_true_peak: -1.5,
    loudness_range: 11,
    auto_normalize: true
  ],

  equalizer: [
    max_gain: 12.0,
    min_gain: -12.0,
    default_bands: %{
      "32" => 0.0,    "64" => 0.0,    "125" => 0.0,
      "250" => 0.0,   "500" => 0.0,   "1000" => 0.0,
      "2000" => 0.0,  "4000" => 0.0,  "8000" => 0.0,
      "16000" => 0.0
    }
  ],

  compressor: [
    default_threshold: -20,
    default_ratio: 3,
    attack_time: 50,
    release_time: 200,
    makeup_gain: 0
  ]

# Конфигурация FFmpeg
config :music_core, MusicCore.AudioStreaming.FFmpeg,
  ffmpeg: [
    path: "ffmpeg",
    buffer_size: 4096,
    sample_rate: 48000,
    channels: 2,
    bitrate: 128,
    codec: "libmp3lame",
    format: "mp3",
    reconnect_attempts: 5,
    reconnect_delay: 1000,
    seek_timeout: 10,
    analyze_duration: 5000000,
    probesize: 5000000,
    threads: 2
  ]

# Конфигурация Redis
config :music_core, :redis,
  host: System.get_env("REDIS_HOST") || "localhost",
  port: System.get_env("REDIS_PORT") || 6379,
  database: 0,
  pool_size: 10

# Конфигурация для взаимодействия с другими сервисами
config :music_core, :services,
  go_processor: [
    host: "localhost",
    port: 8080,
    timeout: 5000
  ],

  java_gateway: [
    host: "localhost",
    port: 8081,
    timeout: 5000
  ]

config :rustler_precompiled, :force_build, tokenizers: true

# Конфигурация для разработки
import_config "#{Mix.env()}.exs"
