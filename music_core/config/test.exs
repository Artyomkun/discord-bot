import Config

# Конфигурация для тестов
config :logger, level: :warn

config :music_core, MusicCore.AudioEffects.Native.DSP,
  lib_path: Path.join(File.cwd!(), "priv/native/audio_effects_native")

config :music_core,
  audio_processing: [
    max_concurrent_streams: 1,
    use_mocks: true
  ]

# Тестовая БД
config :music_core, MusicCore.Buffer,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# Моки для внешних API
config :music_bot, :apis,
  youtube: [enabled: false],
  spotify: [enabled: false],
  use_mocks: true

# Отключаем внешние зависимости в тестах
config :music_core, MusicCore.AudioEffects.Normalizer,
  use_mock_ffmpeg: true

config :music_core, MusicCore.AudioStreaming.DiscordClient,
  ffmpeg: [mock: true]
