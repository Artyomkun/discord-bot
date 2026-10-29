defmodule MusicCore.AudioEffects.Processor.Processor do
  @moduledoc """
  Основной процессор аудио для Discord-бота
  """

  alias MusicCore.{AudioEffects, AudioCache, FFmpeg, FFmpeg.Processor, Statistics, DiscordClient}
  alias MusicCore.AudioEffects.Processor.EffectsConfig
  alias MusicCore.Cache.{RedisClient, Database}
  require Logger

  @default_effects %{
    normalize: true,
    limiter: true,
    volume: 100,
    equalizer: %{bass: 0, mid: 0, treble: 0},
    compressor: %{enabled: false, threshold: 20, ratio: 4, attack: 20, release: 250},
    reverb: %{enabled: false, level: 0.3, room_size: 0.5}
  }

  @doc """
  Обработка аудио через FFmpeg
  """
  def process_audio(audio_stream, user_id, guild_id, audio_source \\ :youtube) do
    Logger.info("🎵 Processing audio for user #{user_id} in guild #{guild_id}")

    with {:ok, raw_stream} <- validate_stream(audio_stream),
         {:ok, effects_config} <- EffectsConfig.get(user_id, guild_id),
         {:ok, output_file} <- Processor.process(raw_stream, effects_config, audio_source) do

      # Кэшируем результат
      cache_audio_processing(guild_id, output_file)

      # Обновляем статистику
      Statistics.record_processed(guild_id, output_file)

      {:ok, %{
        file: output_file,
        guild_id: guild_id,
        effects: effects_config
      }}
    else
      {:error, reason} ->
        Logger.error("Audio processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Пакетная обработка для плэйлистов
  """
  def process_playlist(tracks, user_id, guild_id) do
    Logger.info("Processing playlist with #{length(tracks)} tracks")

    tasks = Enum.map(tracks, fn track ->
      Task.async(fn ->
        case process_audio(track, user_id, guild_id) do
          {:ok, _} -> {:ok, track.id}
          error -> error
        end
      end)
    end)

    results = Task.await_many(tasks, :timer.seconds(30))

    successful = Enum.filter(results, &match?({:ok, _}, &1))
    failed = Enum.filter(results, &match?({:error, _}, &1))

    %{
      total: length(tracks),
      successful: length(successful),
      failed: length(failed),
      failed_tracks: Enum.map(failed, fn {:error, reason} -> reason end)
    }
  end

  @doc """
  Обновление настроек эффектов в реальном времени
  """
  def update_effects(user_id, guild_id, effect_type, params) do
    case get_effects_config(user_id, guild_id) do
      {:ok, current_config} ->
        new_config = deep_merge(current_config, %{effect_type => params})

        # Сохраняем в Redis для сессии
        :ok = RedisClient.set(
          "audio:effects:#{guild_id}:#{user_id}",
          Jason.encode!(new_config),
          ttl: 86_400
        )

        Logger.info("🎚️ Realtime effects not supported with FFmpeg — saved for next track")

        {:ok, new_config}

      error -> error
    end
  end

  @doc """
  Получение статистики обработки
  """
  def get_stats(guild_id) do
    {:ok, %{
      processed_today: AudioCache.get_processed_count(guild_id, :today),
      avg_processing_time: AudioCache.get_avg_time(guild_id),
      active_effects: AudioCache.get_active_effects(guild_id),
      memory_usage: :erlang.memory(:binary)
    }}
  end

  # =========== PRIVATE FUNCTIONS ===========

  defp validate_stream({:ok, stream_data}) when is_binary(stream_data) do
    if byte_size(stream_data) > 0 do
      {:ok, stream_data}
    else
      {:error, :empty_stream}
    end
  end

  defp validate_stream({:error, reason}), do: {:error, reason}
  defp validate_stream(_), do: {:error, :invalid_stream_format}

  defp get_effects_config(user_id, guild_id) do
    # 1. Проверяем Redis (быстрые сессионные настройки)
    case RedisClient.get("audio:effects:#{guild_id}:#{user_id}") do
      {:ok, config_json} ->
        {:ok, Jason.decode!(config_json, keys: :atoms)}

      {:error, _} ->
        # 2. Проверяем БД (постоянные настройки пользователя)
        case Database.get_user_audio_prefs(user_id) do
          {:ok, db_config} ->
            merged_config = Map.merge(@default_effects, db_config)
            {:ok, merged_config}

          {:error, _} ->
            # 3. Используем настройки гильдии
            case Database.get_guild_audio_prefs(guild_id) do
              {:ok, guild_config} ->
                merged_config = Map.merge(@default_effects, guild_config)
                {:ok, merged_config}

              {:error, _} ->
                # 4. Дефолтные настройки
                {:ok, @default_effects}
            end
        end
    end
  end

  defp prepare_ffmpeg_command(processed_data, output_path) do
    base_args = [
      "-i", "pipe:0",
      "-c:a", "libopus",
      "-b:a", "128k",
      "-ar", "48000",
      "-ac", "2",
      "-f", "opus",
      "-y",
      output_path
    ]

    filters = build_audio_filters(processed_data.effects)

    case filters do
      [] -> {:ok, base_args}
      filter_list -> {:ok, base_args ++ ["-af", Enum.join(filter_list, ",")]}
    end
  end

  defp maybe_add_volume(args, volume) when is_number(volume) and volume != 100 do
    vol = volume / 100.0
    args ++ ["-af", "volume=#{vol}"]
  end
  defp maybe_add_volume(args, _), do: args

  defp maybe_add_equalizer(args, %{bass: bass, mid: mid, treble: treble}) when bass != 0 or mid != 0 or treble != 0 do
    eq_filter = "superequalizer=1b=#{bass}:2b=#{mid}:3b=#{treble}"
    args ++ ["-af", eq_filter]
  end
  defp maybe_add_equalizer(args, _), do: args

  defp maybe_add_compressor(args, %{enabled: true, threshold: th, ratio: r, attack: a, release: rel}) do
    comp_filter = "compand=attacks=#{a}:decays=#{rel}:points=-#{th}/-#{th * r}"
    args ++ ["-af", comp_filter]
  end
  defp maybe_add_compressor(args, _), do: args

  defp maybe_add_reverb(args, %{enabled: true, level: level, room_size: size}) do
    reverb_filter = "aecho=#{level * 0.5}:#{level * 0.5}:#{size * 1000}:0.5"
    args ++ ["-af", reverb_filter]
  end
  defp maybe_add_reverb(args, _), do: args

  defp build_audio_filters(effects) do
    []
    |> maybe_add_equalizer(effects.equalizer)
    |> maybe_add_compressor(effects.compressor)
    |> maybe_add_normalization(effects.normalize)
    |> case do
      [] -> []  # нет фильтров
      filters -> ["-af", Enum.join(filters, ",")]
    end
  end

  defp maybe_add_equalizer(filters, nil), do: filters
  defp maybe_add_equalizer(filters, equalizer) when map_size(equalizer) == 0, do: filters
  defp maybe_add_equalizer(filters, equalizer) do
    bass = Map.get(equalizer, :bass, 0.0)
    mid = Map.get(equalizer, :mid, 0.0)
    treble = Map.get(equalizer, :treble, 0.0)

    if bass != 0.0 or mid != 0.0 or treble != 0.0 do
      filters ++ ["superequalizer=1b=#{bass}:2b=#{mid}:3b=#{treble}"]
    else
      filters
    end
  end

  defp maybe_add_compressor(filters, %{enabled: false}), do: filters
  defp maybe_add_compressor(filters, %{enabled: true, threshold: th, ratio: r, attack: a, release: rel}) do
    points = "-#{th}/-#{th * r}|-6/-10"
    filter = "compand=attacks=#{a}:decays=#{rel}:points=#{points}"
    filters ++ [filter]
  end
  defp maybe_add_compressor(filters, _), do: filters

  defp maybe_add_normalization(filters, true) do
    filters ++ ["dynaudnorm"]
  end
  defp maybe_add_normalization(filters, false), do: filters
  defp maybe_add_normalization(filters, _), do: filters

  defp process_with_ffmpeg(input_data, effects_config, guild_id) do
    output_path = "/tmp/audio_#{guild_id}_#{DateTime.utc_now() |> DateTime.to_unix()}.opus"

    case build_ffmpeg_args(effects_config, output_path) do
      {:ok, args} ->
        case Processor.run(input_data, args, output_path) do
          {:ok, _} ->
            DiscordClient.send_audio(guild_id, output_path)

          {:error, reason} ->
            {:error, {:ffmpeg_error, reason}}
        end

      {:error, reason} ->
        {:error, {:ffmpeg_args_error, reason}}
    end
  end

  defp build_ffmpeg_args(effects_config, output_path) do
    base_args = [
      "-i", "pipe:0",
      "-c:a", "libopus",
      "-b:a", "128k",
      "-ar", "48000",
      "-ac", "2",
      "-f", "opus",
      "-y",
      output_path
    ]

    filters = build_audio_filters(effects_config)

    case filters do
      [] -> {:ok, base_args}
      filter_list -> {:ok, base_args ++ ["-af", Enum.join(filter_list, ",")]}
    end
  end

  defp cache_audio_processing(guild_id, file_path) do
    hash = compute_file_hash(file_path)

    key = "processed:#{guild_id}:#{hash}"

    cache_entry = %{
      timestamp: DateTime.utc_now(),
      file_path: file_path,
      hash: hash,
      guild_id: guild_id,
      file_size: File.stat!(file_path).size
    }

    :ok = AudioCache.put(key, cache_entry, ttl: 86_400)
    AudioCache.increment_counter("stats:processed:#{guild_id}")

    {:ok, hash}
  end

  defp compute_file_hash(file_path) do
    file_data = File.read!(file_path)
    :erlang.md5(file_data) |> Base.encode16(case: :lower)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn left_val, right_val ->
      if is_map(left_val) and is_map(right_val) do
        deep_merge(left_val, right_val)
      else
        right_val
      end
    end)
  end
end
