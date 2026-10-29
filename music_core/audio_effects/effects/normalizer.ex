defmodule MusicCore.AudioEffects.Effects.Normalizer do
  @moduledoc """
  Модуль для нормализации громкости аудио по стандарту EBU R128.
  Особенности:
  - Поддержка LUFS (Loudness Units Full Scale) - современный стандарт
  - Автоматический анализ и коррекция
  - Мульти-процессорная обработка (FFmpeg, Rust NIF, Go-сервис)
  - Интеллектуальные пресеты для разных типов контента
  - Пакетная обработка с консистентной громкостью
  """

  @behaviour MusicCore.AudioEffects.Effect

  alias MusicCore.AudioEffects.Native.DSP
  alias MusicCore.AudioEffects.FFmpegWrapper
  alias MusicCore.Services.GoProcessor
  require Logger

  @type normalization_mode :: :ebu_r128 | :rms | :peak | :hybrid | :auto

  @type audio_analysis :: %{
    integrated_loudness: float(),
    loudness_range: float(),
    true_peak: float(),
    sample_rate: integer(),
    channels: integer(),
    duration: float(),
    max_peak: float(),
    rms_level: float(),
    crest_factor: float()
  }

  @default_target_lufs -16.0
  @default_max_true_peak -1.5
  @default_loudness_range 11.0

  @presets %{
    streaming: %{
      target_lufs: -16.0,
      max_true_peak: -1.5,
      loudness_range: 11.0,
      mode: :ebu_r128
    },
    music: %{
      target_lufs: -14.0,
      max_true_peak: -1.0,
      loudness_range: 13.0,
      mode: :hybrid
    },
    speech: %{
      target_lufs: -12.0,
      max_true_peak: -2.0,
      loudness_range: 7.0,
      mode: :ebu_r128
    },
    podcast: %{
      target_lufs: -13.0,
      max_true_peak: -2.0,
      loudness_range: 5.0,
      mode: :hybrid
    },
    broadcast: %{
      target_lufs: -23.0,
      max_true_peak: -1.0,
      loudness_range: 8.0,
      mode: :ebu_r128
    },
    loud: %{
      target_lufs: -10.0,
      max_true_peak: -0.5,
      loudness_range: 6.0,
      mode: :peak
    }
  }

  @impl true
  def apply(audio_stream, config, opts) do
    normalize(audio_stream, config, opts)
  end

  @doc """
  Основная функция нормализации аудио.
  """
  @spec normalize(binary(), atom() | keyword(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def normalize(audio_stream, preset_or_opts \\ :streaming, processor_opts \\ []) do
    start_time = System.monotonic_time()
    {params, opts} = case preset_or_opts do
      preset when is_atom(preset) ->
        preset_config = Map.get(@presets, preset, @presets.streaming)
        {preset_config, processor_opts}

      opts when is_list(opts) ->
        {build_params_from_opts(opts), processor_opts}
    end

    processor = Keyword.get(opts, :processor, :auto)
    result = case processor do
      :ffmpeg -> normalize_with_ffmpeg(audio_stream, params, opts)
      :native -> normalize_with_native(audio_stream, params, opts)
      :go -> normalize_with_go(audio_stream, params, opts)
      :auto -> normalize_auto(audio_stream, params, opts)
    end

    log_normalization_metrics(start_time, byte_size(audio_stream), params, processor, result)

    result
  end

  @doc """
  Автоматическая нормализация с анализом аудио.
  """
  @spec normalize_auto(binary(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def normalize_auto(audio_stream, opts \\ []) do
    case analyze_audio(audio_stream) do
      {:ok, analysis} ->
        params = suggest_normalization_params(analysis, opts)
        processor = suggest_processor(audio_stream, analysis)
        normalize(audio_stream, params, [processor: processor] ++ opts)

      error ->
        error
    end
  end

  @doc """
  Пакетная нормализация нескольких аудио потоков.
  Все потоки приводятся к одинаковой воспринимаемой громкости.
  """
  @spec normalize_batch(list(binary()), keyword()) :: {:ok, list(binary())} | {:error, list(String.t())}
  def normalize_batch([]), do: {:ok, []}

  def normalize_batch(audio_streams, opts \\ []) when is_list(audio_streams) do
    Logger.info("Batch normalizing #{length(audio_streams)} audio streams")

    analyses = Enum.map(audio_streams, &analyze_audio/1)

    {successful_analyses, failed} = Enum.split_with(analyses, &match?({:ok, _}, &1))

    if failed != [] do
      Logger.warning("Failed to analyze #{length(failed)} streams")
    end

    if successful_analyses == [] do
      {:error, ["No streams could be analyzed"]}
    else
      target_lufs = calculate_batch_target_lufs(successful_analyses, opts)

      batch_params = %{
        target_lufs: target_lufs,
        max_true_peak: Keyword.get(opts, :max_true_peak, @default_max_true_peak),
        loudness_range: Keyword.get(opts, :loudness_range, @default_loudness_range),
        mode: :ebu_r128
      }

      results = audio_streams
      |> Enum.zip(successful_analyses)
      |> Task.async_stream(
        fn {stream, {:ok, analysis}} ->
          stream_params = adapt_params_for_stream(batch_params, analysis)
          normalize(stream, stream_params, opts)
        end,
        max_concurrency: Application.get_env(:music_core, :audio_processing, [])[:max_concurrent_streams] || 5,
        timeout: 30000
      )
      |> Enum.to_list()

      aggregate_batch_results(results)
    end
  end

  @doc """
  Интеллектуальная нормализация для музыки с сохранением динамики.
  """
  @spec normalize_music(binary(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def normalize_music(audio_stream, opts \\ []) do
    normalized = case normalize(audio_stream, @presets.music, opts) do
      {:ok, data} -> data
      error -> error
    end

    if Keyword.get(opts, :use_limiter, true) do
      MusicCore.AudioEffects.Effects.Compressor.limit(normalized, -1.0,
        attack: 1,
        release: 50,
        lookahead: Keyword.get(opts, :lookahead_ms, 10)
      )
    else
      {:ok, normalized}
    end
  end

  @doc """
  Агрессивная нормализация для речи.
  """
  @spec normalize_speech(binary(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def normalize_speech(audio_stream, opts \\ []) do
    processed = case FFmpegWrapper.process(audio_stream,
      filters: ["acompressor=threshold=-20dB:ratio=4:attack=20:release=250"],
      output_format: :opus) do
      {:ok, data} -> data
      _ -> audio_stream
    end

    normalize(processed, @presets.speech, opts)
  end

  @doc """
  Детальный анализ аудио потока.
  """
  @spec analyze_audio(binary()) :: {:ok, audio_analysis()} | {:error, atom()}
  def analyze_audio(audio_stream) do
    start_time = System.monotonic_time()

    result = cond do
      System.find_executable("ffmpeg") ->
        analyze_with_ffmpeg(audio_stream)
      Code.ensure_loaded?(DSP) ->
        case DSP.analyze_audio(audio_stream) do
          {:ok, analysis} -> {:ok, analysis}
          _ -> {:error, :analysis_failed}
        end
      true ->
        case GoProcessor.analyze_audio(audio_stream) do
          {:ok, analysis} -> {:ok, analysis}
          _ -> {:error, :no_analyzer_available}
        end
    end

    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    Logger.debug("Audio analysis completed in #{duration_ms}ms")

    result
  end

  @doc """
  Проверяет, нужна ли нормализация аудио.
  """
  @spec needs_normalization?(binary(), float()) :: boolean()
  def needs_normalization?(audio_stream, threshold_db \\ 2.0) do
    case analyze_audio(audio_stream) do
      {:ok, analysis} ->
        deviation = abs(analysis.integrated_loudness - @default_target_lufs)
        peak_ok = analysis.true_peak <= @default_max_true_peak
        deviation > threshold_db or not peak_ok
      _ ->
        true
    end
  end

  @doc """
  Получить рекомендуемые параметры нормализации для аудио.
  """
  @spec suggest_params(binary()) :: map()
  def suggest_params(audio_stream) do
    case analyze_audio(audio_stream) do
      {:ok, analysis} ->
        suggest_normalization_params(analysis, [])
      error ->
        @presets.streaming
    end
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp normalize_with_ffmpeg(audio_stream, params, opts) do
    try do
      filter = build_ffmpeg_filter(params)
      output_format = Keyword.get(opts, :output_format, :opus)
      bitrate = Keyword.get(opts, :bitrate, "128k")
      extra_args = Keyword.get(opts, :ffmpeg_args, [])

      case FFmpegWrapper.process(audio_stream,
          filters: [filter],
          output_format: output_format,
          bitrate: bitrate,
          extra_args: extra_args) do
        {:ok, processed} -> {:ok, processed}
        error -> error
      end
    rescue
      error ->
        Logger.error("FFmpeg normalization failed: #{inspect(error)}")
        {:error, "FFmpeg processing failed"}
    end
  end

  defp normalize_with_native(audio_stream, params, opts) do
    try do
      merged_params = Map.merge(params, Map.new(opts))
      case DSP.normalize_audio(audio_stream, merged_params) do
        {:ok, processed} -> {:ok, processed}
        {:error, reason} ->
          Logger.warning("Native normalization failed: #{reason}, falling back")
          normalize_with_ffmpeg(audio_stream, params, opts)
      end
    rescue
      error ->
        Logger.error("Native normalization failed: #{inspect(error)}")
        {:error, "Native processing failed"}
    end
  end

  defp normalize_with_go(audio_stream, params, opts) do
    case GoProcessor.normalize_audio(audio_stream, Map.merge(params, Map.new(opts))) do
      {:ok, processed} -> {:ok, processed}
      error ->
        Logger.warning("Go normalization failed, falling back to native")
        normalize_with_native(audio_stream, params, opts)
    end
  end

  defp normalize_auto(audio_stream, params, opts) do
    cond do
      Code.ensure_loaded?(DSP) ->
        normalize_with_native(audio_stream, params, opts)
      System.find_executable("ffmpeg") ->
        normalize_with_ffmpeg(audio_stream, params, opts)
      true ->
        normalize_with_go(audio_stream, params, opts)
    end
  end

  defp analyze_with_ffmpeg(audio_stream) do
    temp_file = Path.join(System.tmp_dir!(), "analyze_#{:erlang.unique_integer([:positive])}.opus")

    try do
      File.write!(temp_file, audio_stream)

      {output, 0} = System.cmd("ffmpeg", [
        "-i", temp_file,
        "-af", "loudnorm=print_format=json:I=-16:LRA=11:TP=-1.5",
        "-f", "null", "-"
      ], stderr_to_stdout: true)

      parse_ffmpeg_analysis(output)
    rescue
      error ->
        Logger.error("FFmpeg analysis failed: #{inspect(error)}")
        {:error, :analysis_failed}
    after
      File.rm(temp_file)
    end
  end

  defp parse_ffmpeg_analysis(output) do
    json_match = Regex.run(~r/\{.*\}/s, output)

    case json_match do
      [json_string] ->
        unless Code.ensure_loaded?(Jason) do
          %{error: :jason_not_available}
        end

        case Jason.decode(json_string) do
          {:ok, data} ->
            analysis = %{
              integrated_loudness: data["input_i"] || -23.0,
              loudness_range: data["input_lra"] || 7.0,
              true_peak: data["input_tp"] || -5.0,
              sample_rate: data["sample_rate"] || 48000,
              channels: data["channels"] || 2,
              duration: data["duration"] || 0.0,
              max_peak: :math.pow(10, (data["input_tp"] || -5.0) / 20),
              rms_level: calculate_rms_from_lufs(data["input_i"] || -23.0),
              crest_factor: calculate_crest_factor(data["input_i"] || -23.0, data["input_tp"] || -5.0)
            }
            {:ok, analysis}

          {:error, reason} ->
            Logger.error("Failed to parse analysis JSON: #{reason}")
            {:error, :parse_failed}
        end

      nil ->
        {:error, :no_analysis_data}
    end
  end

  defp build_ffmpeg_filter(params) do
    case params.mode do
      :ebu_r128 ->
        "loudnorm=I=#{params.target_lufs}:LRA=#{params.loudness_range}:TP=#{params.max_true_peak}"
      :rms ->
        "volume=volume=#{calculate_volume_gain(params)}"
      :peak ->
        "volume=volume=#{:math.pow(10, params.max_true_peak / 20)}"
      :hybrid ->
        filters = [
          "acompressor=threshold=-20dB:ratio=3:attack=50:release=250",
          "loudnorm=I=#{params.target_lufs}:LRA=#{params.loudness_range}:TP=#{params.max_true_peak}"
        ]
        Enum.join(filters, ",")
    end
  end

  defp build_params_from_opts(opts) do
    %{
      target_lufs: Keyword.get(opts, :target_lufs, @default_target_lufs),
      max_true_peak: Keyword.get(opts, :max_true_peak, @default_max_true_peak),
      loudness_range: Keyword.get(opts, :loudness_range, @default_loudness_range),
      mode: Keyword.get(opts, :mode, :ebu_r128),
      dynamic_range_preservation: Keyword.get(opts, :dynamic_range_preservation, false),
      use_limiter: Keyword.get(opts, :use_limiter, true),
      lookahead_ms: Keyword.get(opts, :lookahead_ms, 0)
    }
  end

  defp suggest_normalization_params(analysis, opts) do
    target_lufs = cond do
      analysis.integrated_loudness < -25 -> -14.0
      analysis.integrated_loudness < -20 -> -16.0
      analysis.integrated_loudness < -10 -> -18.0
      true -> -20.0
    end

    max_true_peak = cond do
      analysis.true_peak > 0.0 -> -3.0
      analysis.true_peak > -1.0 -> -2.0
      analysis.true_peak > -3.0 -> -1.5
      true -> -1.0
    end

    mode = if analysis.crest_factor > 12 do
      :hybrid
    else
      :ebu_r128
    end

    %{
      target_lufs: Keyword.get(opts, :target_lufs, target_lufs),
      max_true_peak: Keyword.get(opts, :max_true_peak, max_true_peak),
      loudness_range: analysis.loudness_range,
      mode: mode,
      dynamic_range_preservation: analysis.crest_factor > 10
    }
  end

  defp suggest_processor(audio_stream, analysis) do
    size = byte_size(audio_stream)

    cond do
      size > 50_000_000 -> :go
      analysis.true_peak > -0.5 -> :ffmpeg
      Code.ensure_loaded?(DSP) -> :native
      true -> :ffmpeg
    end
  end

  defp calculate_batch_target_lufs(analyses, opts) do
    target = Keyword.get(opts, :target_lufs, :auto)

    case target do
      :auto ->
        lufs_values = Enum.map(analyses, fn {:ok, a} -> a.integrated_loudness end)
        Enum.sum(lufs_values) / length(lufs_values)

      value when is_number(value) ->
        value
    end
  end

  defp adapt_params_for_stream(batch_params, analysis) do
    if analysis.true_peak > -0.5 do
      Map.put(batch_params, :max_true_peak, batch_params.max_true_peak - 1.0)
    else
      batch_params
    end
  end

  defp aggregate_batch_results(results) do
    {successful, failed} = Enum.split_with(results, fn
      {:ok, {:ok, _}} -> true
      _ -> false
    end)

    if failed == [] do
      normalized_streams = Enum.map(successful, fn {:ok, {:ok, stream}} -> stream end)
      {:ok, normalized_streams}
    else
      errors = Enum.map(failed, fn {:ok, {:error, reason}} -> reason end)
      {:error, errors}
    end
  end

  defp calculate_volume_gain(params) do
    gain_linear = :math.pow(10, (params.target_lufs + 23) / 20)
    min(gain_linear, 10.0)
  end

  defp calculate_rms_from_lufs(lufs) do
    lufs - 0.691
  end

  defp calculate_crest_factor(lufs, true_peak) do
    true_peak - lufs
  end

  defp log_normalization_metrics(start_time, size, params, processor, result) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    success? = match?({:ok, _}, result)

    :telemetry.execute([:music_core, :effects, :normalization], %{
      duration: duration_ms,
      size: size,
      success: if(success?, do: 1, else: 0),
      target_lufs: params.target_lufs
    }, %{
      processor: processor,
      mode: params.mode
    })
  end
end
