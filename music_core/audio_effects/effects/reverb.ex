defmodule MusicCore.AudioEffects.Effects.Reverb do
  @moduledoc """
  Модуль для применения эффекта реверберации (эхо, помещение).

  Использует:
  1. FFmpeg для программной реализации
  2. Rust NIF для high-performance обработки
  3. Каскадные фильтры для разных типов помещений
  """
  @behaviour MusicCore.AudioEffects.Effect
  alias MusicCore.AudioEffects.Native.DSP
  alias MusicCore.AudioEffects.FFmpegWrapper
  require Logger
  import Bitwise

  @type reverb_type :: :room | :hall | :church | :plate | :spring | :custom

  @type reverb_preset :: %{
    type: reverb_type,
    room_size: float(),      # 0.0-1.0
    damping: float(),        # 0.0-1.0
    wet_level: float(),      # 0.0-1.0
    dry_level: float(),      # 0.0-1.0
    width: float(),          # 0.0-1.0 (стерео ширина)
    pre_delay: integer(),    # мс
    diffusion: float(),      # 0.0-1.0
    decay: float()           # 0.0-1.0
  }

  @default_presets %{
    room: %{
      type: :room,
      room_size: 0.5,
      damping: 0.5,
      wet_level: 0.3,
      dry_level: 0.7,
      width: 0.8,
      pre_delay: 20,
      diffusion: 0.7,
      decay: 0.5
    },
    hall: %{
      type: :hall,
      room_size: 0.8,
      damping: 0.3,
      wet_level: 0.4,
      dry_level: 0.6,
      width: 1.0,
      pre_delay: 50,
      diffusion: 0.8,
      decay: 0.7
    },
    church: %{
      type: :church,
      room_size: 0.9,
      damping: 0.2,
      wet_level: 0.5,
      dry_level: 0.5,
      width: 0.9,
      pre_delay: 100,
      diffusion: 0.9,
      decay: 0.9
    },
    plate: %{
      type: :plate,
      room_size: 0.6,
      damping: 0.6,
      wet_level: 0.4,
      dry_level: 0.6,
      width: 0.7,
      pre_delay: 10,
      diffusion: 0.6,
      decay: 0.4
    },
    spring: %{
      type: :spring,
      room_size: 0.4,
      damping: 0.4,
      wet_level: 0.6,
      dry_level: 0.4,
      width: 0.5,
      pre_delay: 5,
      diffusion: 0.3,
      decay: 0.3
    }
  }

  @doc """
  Добавляет реверберацию к аудио потоку.
  """
  @spec add(binary(), atom() | reverb_preset(), keyword()) ::
          {:ok, binary()} | {:error, String.t()}
  def add(audio_stream, preset_name_or_config, opts \\ []) do
    start_time = System.monotonic_time()
    processor_type = Keyword.get(opts, :processor, :auto)

    config = get_reverb_config(preset_name_or_config, opts)

    result = case processor_type do
      :ffmpeg -> add_with_ffmpeg(audio_stream, config, opts)
      :native -> add_with_native(audio_stream, config, opts)
      :go -> add_with_go_service(audio_stream, config, opts)
      :auto -> add_auto(audio_stream, config, opts)
    end

    log_processing_metrics(start_time, byte_size(audio_stream), config, result, processor_type)

    result
  end

  @doc """
  Быстрое применение реверба с настройками по умолчанию.
  """
  @spec add_reverb(binary(), float(), float()) :: {:ok, binary()} | {:error, String.t()}
  def add_reverb(audio_stream, room_size \\ 0.5, damping \\ 0.5) do
    add(audio_stream, :custom, room_size: room_size, damping: damping)
  end

  @doc """
  Применяет каскад ревербераций для создания сложного пространства.
  """
  @spec add_cascade(binary(), list(atom() | reverb_preset()), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def add_cascade(audio_stream, cascade_presets, opts \\ []) do
    Enum.reduce_while(cascade_presets, {:ok, audio_stream}, fn preset, {:ok, current_audio} ->
      case add(current_audio, preset, opts) do
        {:ok, new_audio} -> {:cont, {:ok, new_audio}}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Создание кастомного пресета реверберации.
  """
  def create_preset(name, config) when is_map(config) do
    validated_config = validate_reverb_config(config)

    case :ets.info(:reverb_presets) do
      :undefined ->
        :ets.new(:reverb_presets, [:named_table, :public, read_concurrency: true])
      _ ->
        :ok
    end

    :ets.insert(:reverb_presets, {name, validated_config})
    {:ok, name}
  end

  @doc """
  Получить список доступных пресетов.
  """
  def list_presets do
    Map.keys(@default_presets)
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp get_reverb_config(preset_name, opts) when is_atom(preset_name) do
    case Map.get(@default_presets, preset_name) do
      nil ->
        Logger.warning("Unknown reverb preset: #{preset_name}, using :room")
        @default_presets.room

      base_config ->
        Enum.reduce(opts, base_config, fn
          {:room_size, value}, config -> Map.put(config, :room_size, clamp(value, 0.0, 1.0))
          {:damping, value}, config -> Map.put(config, :damping, clamp(value, 0.0, 1.0))
          {:wet_level, value}, config -> Map.put(config, :wet_level, clamp(value, 0.0, 1.0))
          {:dry_level, value}, config -> Map.put(config, :dry_level, clamp(value, 0.0, 1.0))
          {:width, value}, config -> Map.put(config, :width, clamp(value, 0.0, 1.0))
          {:pre_delay, value}, config -> Map.put(config, :pre_delay, max(0, value))
          {:diffusion, value}, config -> Map.put(config, :diffusion, clamp(value, 0.0, 1.0))
          {:decay, value}, config -> Map.put(config, :decay, clamp(value, 0.0, 1.0))
          {_, _}, config -> config
        end)
    end
  end

  defp get_reverb_config(config, opts) when is_map(config) do
    validate_reverb_config(config)
  end

  defp validate_reverb_config(config) do
    %{
      type: Map.get(config, :type, :custom),
      room_size: clamp(Map.get(config, :room_size, 0.5), 0.0, 1.0),
      damping: clamp(Map.get(config, :damping, 0.5), 0.0, 1.0),
      wet_level: clamp(Map.get(config, :wet_level, 0.3), 0.0, 1.0),
      dry_level: clamp(Map.get(config, :dry_level, 0.7), 0.0, 1.0),
      width: clamp(Map.get(config, :width, 0.8), 0.0, 1.0),
      pre_delay: max(Map.get(config, :pre_delay, 20), 0),
      diffusion: clamp(Map.get(config, :diffusion, 0.7), 0.0, 1.0),
      decay: clamp(Map.get(config, :decay, 0.5), 0.0, 1.0)
    }
  end

  defp add_with_ffmpeg(audio_stream, config, opts) do
    try do
      filter = build_ffmpeg_filter(config)
      output_format = Keyword.get(opts, :output_format, :opus)
      bitrate = Keyword.get(opts, :bitrate, "128k")

      case FFmpegWrapper.process(audio_stream, filters: [filter], output_format: output_format, bitrate: bitrate) do
        {:ok, processed} -> {:ok, processed}
        error -> error
      end
    rescue
      error ->
        Logger.error("FFmpeg reverb failed: #{inspect(error)}")
        {:error, "FFmpeg processing failed"}
    end
  end

  defp add_with_native(audio_stream, config, opts) do
    try do
      case DSP.apply_reverb(audio_stream, config) do
        {:ok, processed} -> {:ok, processed}
        {:error, reason} ->
          Logger.warning("Native DSP reverb failed: #{reason}, falling back to FFmpeg")
          add_with_ffmpeg(audio_stream, config, [])
      end
    rescue
      error ->
        Logger.error("Native reverb failed: #{inspect(error)}")
        {:error, "Native processing failed"}
    end
  end

  defp add_with_go_service(audio_stream, config, opts) do
    case MusicCore.Services.GoProcessor.apply_reverb(audio_stream, config) do
      {:ok, processed} -> {:ok, processed}
      error ->
        Logger.warning("Go service reverb failed, falling back to native")
        add_with_native(audio_stream, config, [])
    end
  end

  defp add_auto(audio_stream, config, opts) do
    cond do
      byte_size(audio_stream) > 1_000_000 and Code.ensure_loaded?(DSP) ->
        add_with_native(audio_stream, config, opts)
      System.find_executable("ffmpeg") ->
        add_with_ffmpeg(audio_stream, config, opts)
      true ->
        add_simple_reverb(audio_stream, config)
    end
  end

  defp build_ffmpeg_filter(config) do
    filters = []
    filters = if config.pre_delay > 0 do
      ["adelay=#{config.pre_delay}|#{config.pre_delay}" | filters]
    else
      filters
    end
    delay_ms = round(config.room_size * 500)
    decay_factor = config.damping * 0.9
    echo_filter = "aecho=#{config.wet_level}:#{config.dry_level}:#{delay_ms}:#{decay_factor}"
    filters = [echo_filter | filters]
    filters = if config.width != 1.0 do
      ["stereowiden=#{config.width}" | filters]
    else
      filters
    end
    filters = if config.decay < 1.0 do
      ["aformat=s16:48000:stereo", "volume=#{1.0 - config.decay * 0.5}" | filters]
    else
      filters
    end
    filters
    |> Enum.reverse()
    |> Enum.join(",")
  end

  defp add_simple_reverb(audio_stream, config) do
    try do
      {pcm_data, pcm_format, sample_rate, channels, bit_depth} = extract_pcm_info(audio_stream)
      delay_samples = round(sample_rate * config.pre_delay / 1000)
      decay_rate = 1.0 - config.decay
      delayed = create_delayed_copy(pcm_data, delay_samples, decay_rate)
      mixed = mix_pcm_samples(pcm_data, delayed, config.dry_level, config.wet_level, bit_depth)
      encoded = encode_to_format(mixed, pcm_format, sample_rate, channels, bit_depth)
      {:ok, encoded}
    rescue
      error ->
        Logger.error("Simple reverb failed: #{inspect(error)}")
        {:error, "All reverb methods failed"}
    end
  end

  defp encode_to_format(mixed, :pcm_s16le, sample_rate, channels, bit_depth) do
    mixed = Nx.clip(mixed, -1.0, 1.0)
    max_val = bsl(1, bit_depth - 1) - 1
    scaled = Nx.multiply(mixed, max_val)
    scaled = Nx.as_type(scaled, {:s, bit_depth})
    scaled
    |> Nx.to_binary()
  end

  defp encode_to_format(mixed, :pcm_s32le, sample_rate, channels, bit_depth) do
    mixed = Nx.clip(mixed, -1.0, 1.0)
    max_val = bsl(1, bit_depth - 1) - 1
    scaled = Nx.multiply(mixed, max_val)
    scaled = Nx.as_type(scaled, {:s, bit_depth})
    Nx.to_binary(scaled)
  end

  defp encode_to_format(mixed, :pcm_f32, _sample_rate, _channels, _bit_depth) do
    mixed = Nx.clip(mixed, -1.0, 1.0)
    Nx.as_type(mixed, {:f, 32}) |> Nx.to_binary()
  end

  defp extract_pcm_info(audio_stream) do
    case audio_stream do
      <<0x52, 0x49, 0x46, 0x46, _::binary-size(4),
        0x57, 0x41, 0x56, 0x45,
        0x66, 0x6D, 0x74, 0x20, _::binary-size(4),
        audio_format::little-16,
        channels::little-16,
        sample_rate::little-32,
        byte_rate::little-32,
        block_align::little-16,
        bits_per_sample::little-16,
        _::binary>> ->
        format = case audio_format do
          1 -> :pcm_s16le
          3 -> :pcm_f32le
          _ -> :raw
        end
        data_start = find_data_chunk(audio_stream)
        pcm_data = binary_part(audio_stream, data_start, byte_size(audio_stream) - data_start)

        {pcm_data, format, sample_rate, channels, bits_per_sample}

      _ ->
        {audio_stream, :raw, 48000, 2, 16}
    end
  end

  defp find_data_chunk(bin, offset \\ 12) do
    case bin do
      <<_::binary-size(offset), "data", chunk_size::little-32, _::binary>> ->
        offset + 8
      _ when offset > byte_size(bin) ->
        44
      _ ->
        find_data_chunk(bin, offset + 1)
    end
  end

  defp create_delayed_copy(data, delay_samples, decay_rate) do
    sample_size = 2
    delay_bytes = delay_samples * sample_size

    if delay_bytes >= byte_size(data) do
      apply_decay(data, decay_rate)
    else
      delayed = <<0::size(delay_bytes)-unit(8)>> <> :binary.part(data, 0, byte_size(data) - delay_bytes)
      apply_decay(delayed, decay_rate)
    end
  end

  defp apply_decay(data, decay_rate) do
    if decay_rate <= 0 do
      data
    else
      data
    end
  end

  defp mix_pcm_samples(dry, wet, dry_gain, wet_gain, bit_depth) do
    try do
      # Конвертируем в float32 для смешивания
      dry_float = pcm_to_float(dry, bit_depth)
      wet_float = pcm_to_float(wet, bit_depth)

      # Смешиваем с учётом gain
      mixed_float = Enum.zip(dry_float, wet_float)
      |> Enum.map(fn {d, w} ->
        (d * dry_gain + w * wet_gain) / 2.0
      end)

      # Ограничиваем, чтобы избежать клиппинга
      mixed_float = Enum.map(mixed_float, &clamp_audio/1)

      # Конвертируем обратно в PCM
      float_to_pcm(mixed_float, bit_depth)
    rescue
      error ->
        Logger.error("PCM mixing failed: #{inspect(error)}")
        dry
    end
  end

  defp pcm_to_float(data, bit_depth) do
    case bit_depth do
      8 ->
        for <<sample::8 <- data>>, do: (sample - 128) / 128.0
      16 ->
        for <<sample::16-little <- data>>, do: sample / 32768.0
      24 ->
        for <<b1::8, b2::8, b3::8 <- data>> do
          val = bsl(b1, 16) + bsl(b2, 8) + b3
          val = if (band(val, 0x800000)) != 0, do: val - 0x1000000, else: val
          val / 8388608.0
        end
      32 ->
        for <<sample::32-little-float <- data>>, do: sample
      _ ->
        for <<sample::16-little <- data>>, do: sample / 32768.0
    end
  end

  defp float_to_pcm(samples, bit_depth) do
    case bit_depth do
      8 ->
        for s <- samples, into: <<>> do
          val = round(s * 127.0 + 128) |> clamp(0, 255)
          <<val::8>>
        end
      16 ->
        for s <- samples, into: <<>> do
          val = round(s * 32767.0) |> clamp(-32768, 32767)
          <<val::signed-16-little>>
        end
      24 ->
        for s <- samples, into: <<>> do
          val = round(s * 8388607.0) |> clamp(-8388608, 8388607)
          b1 = band(val, 0xFF)
          b2 = band(bsr(val, 8), 0xFF)
          b3 = band(bsr(val, 16), 0xFF)
          <<b1::8, b2::8, b3::8>>
        end
      32 ->
        for s <- samples, into: <<>> do
          <<s::float-32-little>>
        end
      _ ->
        for s <- samples, into: <<>> do
          val = round(s * 32767.0) |> clamp(-32768, 32767)
          <<val::signed-16-little>>
        end
    end
  end

  defp clamp_audio(sample) when sample > 1.0, do: 1.0
  defp clamp_audio(sample) when sample < -1.0, do: -1.0
  defp clamp_audio(sample), do: sample

  defp clamp(value, min, max) when value < min, do: min
  defp clamp(value, min, max) when value > max, do: max
  defp clamp(value, min, max), do: value

  defp log_processing_metrics(start_time, size, config, result, processor_type) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    success? = match?({:ok, _}, result)

    :telemetry.execute([:music_core, :effects, :reverb], %{
      duration: duration_ms,
      size: size,
      success: if(success?, do: 1, else: 0),
      room_size: config.room_size,
      processor: processor_type
    }, %{
      type: config.type
    })
  end
end
