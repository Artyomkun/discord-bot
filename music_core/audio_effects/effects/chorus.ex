defmodule MusicCore.AudioEffects.Effects.Chorus do
  @moduledoc """
  Модуль для применения эффекта хорус (Chorus).
  Хорус создаёт эффект "хора" путём добавления нескольких задержанных копий
  сигнала с модуляцией по частоте. Создаёт ощущение пространства и глубины.

  Особенности:
  - Многоголосный хорус (до 8 голосов)
  - Модуляция LFO (синус, треугольник, прямоугольник)
  - Стерео расширение
  - Разные тональные характеристики (warm, bright, dark)
  - Паттерны для разных инструментов
  """

  @behaviour MusicCore.AudioEffects.Effect

  alias MusicCore.AudioEffects.Native.DSP
  alias MusicCore.AudioEffects.FFmpegWrapper
  alias MusicCore.Services.GoProcessor
  require Logger

  @type lfo_waveform :: :sine | :triangle | :square

  @type chorus_voice :: %{
    delay_ms: float(),
    depth_ms: float(),
    rate_hz: float(),
    gain: float(),
    phase: float(),
    waveform: lfo_waveform(),
    stereo: boolean()
  }

  @type chorus_config :: %{
    voices: list(chorus_voice()),
    mix: float(),
    feedback: float(),
    stereo_width: float(),
    predelay_ms: float(),
    output_gain: float(),
    tone: :warm | :bright | :dark
  }

  @default_presets %{
    classic: %{
      voices: [
        %{delay_ms: 20, depth_ms: 5, rate_hz: 0.5, gain: 0.6, phase: 0, waveform: :sine},
        %{delay_ms: 25, depth_ms: 6, rate_hz: 0.7, gain: 0.5, phase: 90, waveform: :sine},
        %{delay_ms: 30, depth_ms: 7, rate_hz: 0.9, gain: 0.4, phase: 180, waveform: :sine},
        %{delay_ms: 35, depth_ms: 8, rate_hz: 1.1, gain: 0.3, phase: 270, waveform: :sine}
      ],
      mix: 0.5,
      feedback: 0.1,
      stereo_width: 0.8,
      predelay_ms: 0,
      output_gain: 1.0,
      tone: :warm
    },

    vintage: %{
      voices: [
        %{delay_ms: 30, depth_ms: 10, rate_hz: 0.4, gain: 0.7, phase: 0, waveform: :triangle},
        %{delay_ms: 40, depth_ms: 12, rate_hz: 0.5, gain: 0.5, phase: 120, waveform: :triangle},
        %{delay_ms: 50, depth_ms: 15, rate_hz: 0.6, gain: 0.3, phase: 240, waveform: :triangle}
      ],
      mix: 0.6,
      feedback: 0.15,
      stereo_width: 0.9,
      predelay_ms: 5,
      output_gain: 0.9,
      tone: :warm
    },

    modern: %{
      voices: [
        %{delay_ms: 15, depth_ms: 4, rate_hz: 1.2, gain: 0.5, phase: 0, waveform: :sine},
        %{delay_ms: 18, depth_ms: 5, rate_hz: 1.4, gain: 0.4, phase: 120, waveform: :sine},
        %{delay_ms: 21, depth_ms: 6, rate_hz: 1.6, gain: 0.3, phase: 240, waveform: :sine}
      ],
      mix: 0.4,
      feedback: 0.05,
      stereo_width: 1.0,
      predelay_ms: 0,
      output_gain: 1.0,
      tone: :bright
    },

    deep_space: %{
      voices: [
        %{delay_ms: 50, depth_ms: 25, rate_hz: 0.2, gain: 0.8, phase: 0, waveform: :triangle},
        %{delay_ms: 60, depth_ms: 30, rate_hz: 0.25, gain: 0.6, phase: 144, waveform: :sine},
        %{delay_ms: 70, depth_ms: 35, rate_hz: 0.3, gain: 0.4, phase: 216, waveform: :sine},
        %{delay_ms: 80, depth_ms: 40, rate_hz: 0.35, gain: 0.3, phase: 288, waveform: :triangle}
      ],
      mix: 0.8,
      feedback: 0.2,
      stereo_width: 1.0,
      predelay_ms: 10,
      output_gain: 0.7,
      tone: :warm
    },

    vocal: %{
      voices: [
        %{delay_ms: 25, depth_ms: 6, rate_hz: 0.6, gain: 0.4, phase: 0, waveform: :sine},
        %{delay_ms: 30, depth_ms: 7, rate_hz: 0.7, gain: 0.3, phase: 180, waveform: :sine}
      ],
      mix: 0.35,
      feedback: 0.0,
      stereo_width: 0.6,
      predelay_ms: 0,
      output_gain: 1.0,
      tone: :dark
    },

    guitar: %{
      voices: [
        %{delay_ms: 20, depth_ms: 8, rate_hz: 0.8, gain: 0.5, phase: 0, waveform: :sine},
        %{delay_ms: 25, depth_ms: 10, rate_hz: 1.0, gain: 0.4, phase: 90, waveform: :triangle},
        %{delay_ms: 30, depth_ms: 12, rate_hz: 1.2, gain: 0.3, phase: 180, waveform: :sine},
        %{delay_ms: 35, depth_ms: 14, rate_hz: 1.4, gain: 0.2, phase: 270, waveform: :triangle}
      ],
      mix: 0.55,
      feedback: 0.1,
      stereo_width: 0.85,
      predelay_ms: 0,
      output_gain: 1.0,
      tone: :bright
    }
  }

  @impl true
  def apply(audio_stream, config, opts) do
    add_chorus(audio_stream, config, opts)
  end

  @doc """
  Основная функция добавления хоруса к аудио.
  """
  @spec add_chorus(binary(), atom() | chorus_config(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def add_chorus(audio_stream, config, opts \\ []) do
    start_time = System.monotonic_time()
    chorus_config = get_chorus_config(config, opts)
    processor = Keyword.get(opts, :processor, :auto)

    result = case processor do
      :ffmpeg -> add_with_ffmpeg(audio_stream, chorus_config, opts)
      :native -> add_with_native(audio_stream, chorus_config, opts)
      :go -> add_with_go(audio_stream, chorus_config, opts)
      :auto -> add_auto(audio_stream, chorus_config, opts)
    end

    log_chorus_metrics(start_time, byte_size(audio_stream), chorus_config, processor, result)
    result
  end

  @doc """
  Быстрый хорус с настройкой количества голосов.
  """
  @spec quick_chorus(binary(), integer(), float()) :: {:ok, binary()} | {:error, String.t()}
  def quick_chorus(audio_stream, num_voices \\ 4, mix \\ 0.5) do
    config = %{
      voices: build_default_voices(num_voices),
      mix: clamp(mix, 0.0, 1.0),
      feedback: 0.1,
      stereo_width: 0.8,
      predelay_ms: 0,
      output_gain: 1.0,
      tone: :warm
    }
    add_chorus(audio_stream, config)
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp get_chorus_config(preset, opts) when is_atom(preset) do
    case Map.get(@default_presets, preset) do
      nil ->
        Logger.warning("Unknown chorus preset: #{preset}, using :classic")
        @default_presets.classic

      base_config ->
        merge_with_opts(base_config, opts)
    end
  end

  defp get_chorus_config(config, opts) when is_map(config) do
    merge_with_opts(config, opts)
  end

  defp merge_with_opts(base_config, opts) do
    Enum.reduce(opts, base_config, fn
      {:mix, value}, acc -> Map.put(acc, :mix, clamp(value, 0.0, 1.0))
      {:feedback, value}, acc -> Map.put(acc, :feedback, clamp(value, 0.0, 1.0))
      {:stereo_width, value}, acc -> Map.put(acc, :stereo_width, clamp(value, 0.0, 1.0))
      {:predelay_ms, value}, acc -> Map.put(acc, :predelay_ms, max(0, value))
      {:output_gain, value}, acc -> Map.put(acc, :output_gain, max(0, value))
      {:tone, value}, acc when value in [:warm, :bright, :dark] -> Map.put(acc, :tone, value)
      {_, _}, acc -> acc
    end)
    |> validate_chorus_config()
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
        Logger.error("FFmpeg chorus failed: #{inspect(error)}")
        {:error, "FFmpeg processing failed"}
    end
  end

  defp add_with_native(audio_stream, config, opts) do
    try do
      case DSP.apply_chorus(audio_stream, config) do
        {:ok, processed} -> {:ok, processed}
        {:error, reason} ->
          Logger.warning("Native chorus failed: #{reason}, falling back to FFmpeg")
          add_with_ffmpeg(audio_stream, config, [])
      end
    rescue
      error ->
        Logger.error("Native chorus failed: #{inspect(error)}")
        {:error, "Native processing failed"}
    end
  end

  defp add_with_go(audio_stream, config, opts) do
    case GoProcessor.apply_chorus(audio_stream, config) do
      {:ok, processed} -> {:ok, processed}
      error ->
        Logger.warning("Go chorus failed, falling back to native")
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
        {:error, "No chorus processor available"}
    end
  end

  defp build_ffmpeg_filter(config) do
    voices = config.voices
    sample_rate = 48000

    filter = Enum.with_index(voices, 1)
    |> Enum.map(fn {voice, idx} ->
      delay_ms = voice.delay_ms
      depth_ms = voice.depth_ms
      rate_hz = voice.rate_hz
      delay_samples = round(delay_ms * sample_rate / 1000)

      chorus_filter = "chorus=#{voice.gain}:1:#{delay_samples}:#{depth_ms}:1:" <>
                      "#{delay_samples}:1:#{depth_ms}:1:#{rate_hz}:#{rate_hz}"

      "[0:a]#{chorus_filter}[chorus#{idx}]"
    end)
    |> Enum.join(";")

    filter = if length(config.voices) > 1 do
      mix_inputs = Enum.map(1..length(config.voices), &"[chorus#{&1}]") |> Enum.join("")
      mix_filter = "#{mix_inputs}amix=inputs=#{length(config.voices)}:duration=longest[mixed]"
      [filter, mix_filter]
      |> Enum.join(";")
    else
      filter
    end

    filter = if config.mix != 1.0 do
      filter <> ";aeval=val(0)|val(1)"
    else
      filter
    end

    filter
  end

  defp build_default_voices(num_voices) do
    Enum.map(1..num_voices, fn i ->
      ratio = i / num_voices
      %{
        delay_ms: 20 + i * 5,
        depth_ms: 5 + i * 1.5,
        rate_hz: 0.5 + i * 0.15,
        gain: 0.7 - ratio * 0.5,
        phase: i * 360 / num_voices,
        waveform: :sine,
        stereo: rem(i, 2) == 0
      }
    end)
  end

  defp validate_chorus_config(config) do
    %{
      voices: validate_voices(Map.get(config, :voices, [])),
      mix: clamp(Map.get(config, :mix, 0.5), 0.0, 1.0),
      feedback: clamp(Map.get(config, :feedback, 0.1), 0.0, 1.0),
      stereo_width: clamp(Map.get(config, :stereo_width, 0.8), 0.0, 1.0),
      predelay_ms: max(Map.get(config, :predelay_ms, 0), 0),
      output_gain: max(Map.get(config, :output_gain, 1.0), 0),
      tone: Map.get(config, :tone, :warm)
    }
  end

  defp validate_voices(voices) when is_list(voices) do
    Enum.map(voices, fn voice ->
      %{
        delay_ms: max(Map.get(voice, :delay_ms, 20), 0),
        depth_ms: max(Map.get(voice, :depth_ms, 5), 0),
        rate_hz: max(Map.get(voice, :rate_hz, 0.5), 0.01),
        gain: clamp(Map.get(voice, :gain, 0.5), 0.0, 1.0),
        phase: Map.get(voice, :phase, 0),
        waveform: Map.get(voice, :waveform, :sine),
        stereo: Map.get(voice, :stereo, false)
      }
    end)
  end

  defp clamp(value, min, max) when value < min, do: min
  defp clamp(value, min, max) when value > max, do: max
  defp clamp(value, _, _), do: value

  defp log_chorus_metrics(start_time, size, config, processor, result) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    success? = match?({:ok, _}, result)

    :telemetry.execute([:music_core, :effects, :chorus], %{
      duration: duration_ms,
      size: size,
      success: if(success?, do: 1, else: 0),
      num_voices: length(config.voices),
      mix: config.mix
    }, %{
      processor: processor,
      tone: config.tone
    })
  end
end
