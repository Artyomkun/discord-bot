defmodule MusicCore.Config do
  def load do
    # Загружаем конфигурацию FFmpeg
    ffmpeg_config = Application.get_env(:music_core, MusicCore.AudioStreaming.FFmpeg, [])
                    |> Keyword.get(:ffmpeg, %{})

    # Загружаем конфигурацию Redis
    redis_config = Application.get_env(:music_core, :redis, %{})

    # Загружаем конфигурацию сервисов
    services_config = Application.get_env(:music_core, :services, [])
    go_config = Keyword.get(services_config, :go_processor, %{})
    java_config = Keyword.get(services_config, :java_gateway, %{})

    # Загружаем конфигурацию аудио эффектов
    effects_config = Application.get_env(:music_core, MusicCore.AudioEffects.Processor.EffectsConfig, [])
    normalizer_config = Keyword.get(effects_config, :normalizer, %{})
    equalizer_config = Keyword.get(effects_config, :equalizer, %{})
    compressor_config = Keyword.get(effects_config, :compressor, %{})

    %{
      # HTTP
      http_port: Application.get_env(:music_core, :http_port, 4000),

      # FFmpeg
      ffmpeg_path: ffmpeg_config[:path] || "ffmpeg",
      ffmpeg_buffer_size: ffmpeg_config[:buffer_size] || 4096,
      ffmpeg_sample_rate: ffmpeg_config[:sample_rate] || 48000,
      ffmpeg_channels: ffmpeg_config[:channels] || 2,
      ffmpeg_bitrate: ffmpeg_config[:bitrate] || 128,
      ffmpeg_codec: ffmpeg_config[:codec] || "libmp3lame",
      ffmpeg_format: ffmpeg_config[:format] || "mp3",
      ffmpeg_reconnect_attempts: ffmpeg_config[:reconnect_attempts] || 3,
      ffmpeg_reconnect_delay: ffmpeg_config[:reconnect_delay] || 1000,

      # Redis
      redis_host: redis_config[:host] || "localhost",
      redis_port: redis_config[:port] || 6379,
      redis_database: redis_config[:database] || 0,
      redis_pool_size: redis_config[:pool_size] || 10,

      # Go Processor
      go_host: go_config[:host] || "localhost",
      go_port: go_config[:port] || 8080,
      go_timeout: go_config[:timeout] || 5000,

      # Java Gateway
      java_host: java_config[:host] || "localhost",
      java_port: java_config[:port] || 8081,
      java_timeout: java_config[:timeout] || 5000,

      # Audio Processing
      max_concurrent_streams: Application.get_env(:music_core, :audio_processing, []) |> Keyword.get(:max_concurrent_streams, 10),
      max_queue_size: Application.get_env(:music_core, :audio_processing, []) |> Keyword.get(:max_queue_size, 100),
      default_bitrate: Application.get_env(:music_core, :audio_processing, []) |> Keyword.get(:default_bitrate, 128),

      # Normalizer
      normalizer_target_lufs: normalizer_config[:target_lufs] || -16,
      normalizer_max_true_peak: normalizer_config[:max_true_peak] || -1.5,
      normalizer_loudness_range: normalizer_config[:loudness_range] || 11,
      normalizer_auto_normalize: normalizer_config[:auto_normalize] || true,

      # Equalizer
      equalizer_max_gain: equalizer_config[:max_gain] || 12.0,
      equalizer_min_gain: equalizer_config[:min_gain] || -12.0,
      equalizer_default_bands: equalizer_config[:default_bands] || %{
        "32" => 0.0, "64" => 0.0, "125" => 0.0,
        "250" => 0.0, "500" => 0.0, "1000" => 0.0,
        "2000" => 0.0, "4000" => 0.0, "8000" => 0.0,
        "16000" => 0.0
      },

      # Compressor
      compressor_default_threshold: compressor_config[:default_threshold] || -20,
      compressor_default_ratio: compressor_config[:default_ratio] || 3,
      compressor_attack_time: compressor_config[:attack_time] || 50,
      compressor_release_time: compressor_config[:release_time] || 200,
      compressor_makeup_gain: compressor_config[:makeup_gain] || 0
    }
  end
end
