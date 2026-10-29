defmodule MusicCore.AudioEffects.Effects.Compressor do
  @moduledoc """
  Модуль для динамической компрессии аудио.

  Реализует профессиональные алгоритмы динамической обработки:
  - Компрессор (Compressor) - уменьшение динамического диапазона
  - Лимитер (Limiter) - защита от клиппинга
  - Экспандер (Expander) - увеличение динамического диапазона
  - Гейт (Gate) - удаление шумов

  Поддерживает многополосную компрессию и side-chain обработку.
  """
  @behaviour MusicCore.AudioEffects.Effect
  alias MusicCore.AudioEffects.Native.DSP
  alias MusicCore.AudioEffects.FFmpegWrapper
  alias MusicCore.Services.GoProcessor
  import MusicCore.AudioEffects.Effects.Reverb, only: [add: 3]
  require Logger
  import Bitwise

  @type compressor_type :: :compressor | :limiter | :expander | :gate | :multiband | :parallel | :sidechain

  @type compressor_params :: %{
    type: compressor_type,
    threshold: float(),
    ratio: float(),
    attack: integer(),
    release: integer(),
    knee: float(),
    makeup_gain: float(),
    lookahead: integer(),
    auto_release: boolean(),
    mix: float(),
    sidechain_source: binary() | nil
  }

  @type multiband_band :: %{
    freq_low: float(),
    freq_high: float(),
    threshold: float(),
    ratio: float(),
    attack: integer(),
    release: integer(),
    solo: boolean(),
    mute: boolean()
  }

  @type audio_info :: %{
    sample_rate: integer(),
    channels: integer(),
    bit_depth: integer(),
    format: atom(),
    data: binary(),
    frames: integer()
  }

  @default_presets %{
    transparent: %{
      type: :compressor,
      threshold: -24.0,
      ratio: 2.0,
      attack: 30,
      release: 150,
      knee: 6.0,
      makeup_gain: 2.0,
      lookahead: 0,
      auto_release: true,
      mix: 1.0
    },

    aggressive: %{
      type: :compressor,
      threshold: -12.0,
      ratio: 8.0,
      attack: 5,
      release: 50,
      knee: 0.0,
      makeup_gain: 8.0,
      lookahead: 5,
      auto_release: false,
      mix: 1.0
    },

    vocal: %{
      type: :compressor,
      threshold: -20.0,
      ratio: 4.0,
      attack: 20,
      release: 100,
      knee: 3.0,
      makeup_gain: 4.0,
      lookahead: 10,
      auto_release: true,
      mix: 1.0
    },

    bass: %{
      type: :compressor,
      threshold: -15.0,
      ratio: 6.0,
      attack: 50,
      release: 200,
      knee: 6.0,
      makeup_gain: 3.0,
      lookahead: 0,
      auto_release: true,
      mix: 1.0
    },

    mastering: %{
      type: :limiter,
      threshold: -1.5,
      ratio: 20.0,
      attack: 1,
      release: 50,
      knee: 0.0,
      makeup_gain: 0.0,
      lookahead: 10,
      auto_release: false,
      mix: 1.0
    },

    noise_gate: %{
      type: :gate,
      threshold: -40.0,
      ratio: 100.0,
      attack: 1,
      release: 100,
      knee: 0.0,
      makeup_gain: 0.0,
      lookahead: 0,
      auto_release: false,
      mix: 1.0
    },

    multiband_mastering: %{
      type: :multiband,
      bands: [
        %{freq_low: 20, freq_high: 150, threshold: -24, ratio: 2, attack: 30, release: 200},  # Sub
        %{freq_low: 150, freq_high: 800, threshold: -18, ratio: 3, attack: 20, release: 150},  # Low mid
        %{freq_low: 800, freq_high: 3000, threshold: -20, ratio: 2.5, attack: 15, release: 100},  # Mid
        %{freq_low: 3000, freq_high: 12000, threshold: -15, ratio: 4, attack: 10, release: 80},  # High mid
        %{freq_low: 12000, freq_high: 20000, threshold: -10, ratio: 6, attack: 5, release: 50}   # High
      ],
      makeup_gain: 0.0,
      mix: 1.0
    }
  }

  @impl true
  def apply(audio_stream, config, opts) do
    add(audio_stream, config, opts)
  end

  @doc """
  Основная функция компрессии аудио.
  """
  def compress(audio_stream, threshold_or_preset, ratio_or_opts \\ nil, opts \\ []) do
    start_time = System.monotonic_time()
    {params, actual_opts} = case {threshold_or_preset, ratio_or_opts} do
      {threshold, ratio} when is_number(threshold) and is_number(ratio) ->
        {%{
          threshold: threshold,
          ratio: ratio,
          attack: 20,
          release: 250,
          knee: 6.0,
          makeup_gain: 0.0
        }, opts}

      {preset, maybe_opts} when is_atom(preset) and (is_list(maybe_opts) or is_nil(maybe_opts)) ->
        {get_compressor_params(preset, maybe_opts || []), maybe_opts || []}

      {params, maybe_opts} when is_map(params) and (is_list(maybe_opts) or is_nil(maybe_opts)) ->
        {params, maybe_opts || []}

      {opts, nil} when is_list(opts) ->
        {get_compressor_params(:transparent, opts), opts}

      _ ->
        {get_compressor_params(:transparent, []), []}
    end

    processor = Keyword.get(actual_opts, :processor, :auto)

    result = case processor do
      :ffmpeg -> compress_with_ffmpeg(audio_stream, params, actual_opts)
      :native -> compress_with_native(audio_stream, params, actual_opts)
      :go -> compress_with_go(audio_stream, params, actual_opts)
      :auto -> compress_auto(audio_stream, params, actual_opts)
    end

    log_compression_metrics(start_time, byte_size(audio_stream), params, processor, result)
    result
  end

  @doc """
  Лимитер быстрый компрессор с высоким ratio.
  """
  def limit(audio_stream, threshold_or_params \\ -1.0, opts \\ []) do
    params = case threshold_or_params do
      threshold when is_number(threshold) ->
        %{
          type: :limiter,
          threshold: threshold,
          ratio: 20.0,
          attack: 1,
          release: 50,
          knee: 0.0,
          makeup_gain: 0.0,
          lookahead: 10
        }

      params when is_map(params) ->
        Map.merge(%{
          type: :limiter,
          threshold: -1.0,
          ratio: 20.0,
          attack: 1,
          release: 50,
          knee: 0.0,
          makeup_gain: 0.0,
          lookahead: 10
        }, params)

      _ ->
        %{
          type: :limiter,
          threshold: -1.0,
          ratio: 20.0,
          attack: 1,
          release: 50,
          knee: 0.0,
          makeup_gain: 0.0,
          lookahead: 10
        }
    end

    compress(audio_stream, params, opts)
  end

  @doc """
  Экспандер для увеличения динамического диапазона.
  """
  def expand(audio_stream, threshold_or_params \\ -30, ratio_or_opts \\ 0.5, opts \\ []) do
    {params, actual_opts} = case {threshold_or_params, ratio_or_opts} do
      {threshold, ratio} when is_number(threshold) and is_number(ratio) ->
        {%{
          type: :expander,
          threshold: threshold,
          ratio: ratio,
          attack: 10,
          release: 100,
          knee: 3.0,
          makeup_gain: 0.0
        }, opts}

      {params, maybe_opts} when is_map(params) and (is_list(maybe_opts) or is_nil(maybe_opts)) ->
        {Map.merge(%{
          type: :expander,
          threshold: -30,
          ratio: 0.5,
          attack: 10,
          release: 100,
          knee: 3.0,
          makeup_gain: 0.0
        }, params), maybe_opts || []}

      {opts, nil} when is_list(opts) ->
        {%{
          type: :expander,
          threshold: -30,
          ratio: 0.5,
          attack: 10,
          release: 100,
          knee: 3.0,
          makeup_gain: 0.0
        }, opts}

      _ ->
        {%{
          type: :expander,
          threshold: -30,
          ratio: 0.5,
          attack: 10,
          release: 100,
          knee: 3.0,
          makeup_gain: 0.0
        }, []}
    end

    compress(audio_stream, params, actual_opts)
  end

  @doc """
  Нойз-гейт для удаления фонового шума.
  """
  def gate(audio_stream, threshold_or_params \\ -40, opts \\ []) do
    params = case threshold_or_params do
      threshold when is_number(threshold) ->
        %{
          type: :gate,
          threshold: threshold,
          ratio: 100.0,
          attack: 1,
          release: 100,
          knee: 0.0,
          hold: 50,
          range: -80.0
        }
      param_map when is_map(param_map) ->
        Map.merge(%{
          type: :gate,
          threshold: -40,
          ratio: 100.0,
          attack: 1,
          release: 100,
          knee: 0.0,
          hold: 50,
          range: -80.0
        }, param_map)
      _ ->
        %{
          type: :gate,
          threshold: -40,
          ratio: 100.0,
          attack: 1,
          release: 100,
          knee: 0.0,
          hold: 50,
          range: -80.0
        }
    end

    compress(audio_stream, params, opts)
  end

  @doc """
  Многополосная компрессия.
  """
  def multiband_compress(audio_stream, bands, opts \\ []) when is_list(bands) do
    with {:ok, validated} <- validate_multiband_bands(bands) do
      params = %{
        type: :multiband,
        bands: validated,
        makeup_gain: Keyword.get(opts, :makeup_gain, 0.0),
        mix: Keyword.get(opts, :mix, 1.0)
      }
      compress(audio_stream, params, opts)
    end
  end

  @doc """
  Parallel compression (NY compression) - техника для сохранения атаки.
  """
  def parallel_compress(audio_stream, params, opts \\ []) do
    mix_ratio = Keyword.get(opts, :mix_ratio, 0.5)
    {dry, wet} = split_signal(audio_stream, mix_ratio)

    case compress(wet, params, opts) do
      {:ok, compressed_wet} ->
        {:ok, mix_signals(dry, compressed_wet, mix_ratio)}
      error -> error
    end
  end

  @doc """
  Side-chain компрессия (ducking).
  """
  def sidechain_compress(audio_stream, sidechain_source, params, opts \\ []) do
    case analyze_envelope(sidechain_source) do
      {:ok, envelope} when is_list(envelope) ->
        compress(audio_stream, Map.merge(params, %{
          type: :sidechain,
          sidechain_envelope: envelope
        }), opts)
      {:ok, envelope} ->
        compress(audio_stream, Map.merge(params, %{
          type: :sidechain,
          sidechain_envelope: [envelope]
        }), opts)
      error -> error
    end
  end

  @doc """
  Автоматическая настройка компрессора на основе анализа аудио.
  """
  def auto_compress(audio_stream, opts \\ []) do
    case analyze_dynamics(audio_stream) do
      {:ok, analysis} ->
        params = suggest_compressor_params(analysis, opts)
        compressor_type = suggest_compressor_type(analysis)
        compress(audio_stream, Map.put(params, :type, compressor_type), opts)
      _ ->
        compress(audio_stream, %{type: :compressor, threshold: -24, ratio: 4}, opts)
    end
  end

  @doc """
  Анализ динамики аудио для подбора параметров компрессора.
  """
  def analyze_dynamics(audio_stream) do
    temp_file = Path.join(System.tmp_dir!(), "dynamics_#{:erlang.unique_integer([:positive])}.opus")

    try do
      File.write!(temp_file, audio_stream)
      if Code.ensure_loaded?(DSP) do
        DSP.analyze_dynamics(audio_stream)
      else
        analyze_dynamics_with_ffmpeg(temp_file)
      end
    rescue
      error ->
        Logger.error("Dynamics analysis failed: #{inspect(error)}")
        {:error, :analysis_failed}
    after
      File.rm(temp_file)
    end
  end

  @doc """
  Создание кастомного пресета компрессора.
  """
  def create_preset(name, params) when is_map(params) do
    validated_params = validate_compressor_params(params)

    # Сохраняем в ETS
    :ets.insert(:compressor_presets, {name, validated_params})

    {:ok, name, validated_params}
  end

  @doc """
  Получить список доступных пресетов.
  """
  def list_presets do
    Map.keys(@default_presets)
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp get_compressor_params(preset_name, opts) when is_atom(preset_name) do
    case Map.get(@default_presets, preset_name) do
      nil ->
        Logger.warning("Unknown compressor preset: #{preset_name}, using :transparent")
        @default_presets.transparent

      base_params ->
        merge_with_opts(base_params, opts)
    end
  end

  defp get_compressor_params(params, opts) when is_map(params) do
    merge_with_opts(params, opts)
  end

  defp get_compressor_params(opts, _) when is_list(opts) do
    params = Enum.into(opts, %{}, fn
      {key, value} -> {key, value}
    end)

    merge_with_opts(@default_presets.transparent, params)
  end

  defp merge_with_opts(base_params, opts) do
    Enum.reduce(opts, base_params, fn
      {:threshold, value}, params -> Map.put(params, :threshold, value)
      {:ratio, value}, params -> Map.put(params, :ratio, value)
      {:attack, value}, params -> Map.put(params, :attack, max(0, value))
      {:release, value}, params -> Map.put(params, :release, max(0, value))
      {:knee, value}, params -> Map.put(params, :knee, max(0.0, value))
      {:makeup_gain, value}, params -> Map.put(params, :makeup_gain, value)
      {:lookahead, value}, params -> Map.put(params, :lookahead, max(0, value))
      {:mix, value}, params -> Map.put(params, :mix, clamp(value, 0.0, 1.0))
      {_, _}, params -> params
    end)
    |> validate_compressor_params()
  end

  defp compress_with_ffmpeg(audio_stream, params, opts) do
    try do
      filter = build_ffmpeg_filter(params)
      output_format = Keyword.get(opts, :output_format, :opus)
      bitrate = Keyword.get(opts, :bitrate, "128k")
      additional_args = Keyword.get(opts, :ffmpeg_args, [])

      case FFmpegWrapper.process(audio_stream,
          filters: [filter],
          output_format: output_format,
          bitrate: bitrate,
          extra_args: additional_args) do
        {:ok, processed} -> {:ok, processed}
        error -> error
      end
    rescue
      error ->
        Logger.error("FFmpeg compression failed: #{inspect(error)}")
        {:error, "FFmpeg processing failed"}
    end
  end

  defp compress_with_native(audio_stream, params, opts) do
    try do
      case DSP.compress_audio(audio_stream, params) do
        {:ok, processed} -> {:ok, processed}
        {:error, reason} ->
          Logger.warning("Native compression failed: #{reason}, falling back")
          compress_with_ffmpeg(audio_stream, params, [])
      end
    rescue
      error ->
        Logger.error("Native compression failed: #{inspect(error)}")
        {:error, "Native processing failed"}
    end
  end

  defp compress_with_go(audio_stream, params, opts) do
    case GoProcessor.compress_audio(audio_stream, params) do
      {:ok, processed} -> {:ok, processed}
      {:error, reason} ->
        Logger.warning("Go compression failed: #{inspect(reason)}, falling back to native")
        compress_with_native(audio_stream, params, [])
    end
  end

  defp compress_auto(audio_stream, params, opts) do
    cond do
      params.type in [:multiband, :parallel, :sidechain] ->
        compress_with_ffmpeg(audio_stream, params, opts)
      Code.ensure_loaded?(DSP) and params.type in [:compressor, :limiter, :expander, :gate] ->
        compress_with_native(audio_stream, params, opts)
      true ->
        compress_with_ffmpeg(audio_stream, params, opts)
    end
  end

  defp build_ffmpeg_filter(params) do
    case params.type do
      :compressor ->
        threshold = params.threshold
        ratio = params.ratio
        attack = params.attack
        release = params.release
        knee = params.knee
        makeup = params.makeup_gain
        "acompressor=threshold=#{threshold}dB:ratio=#{ratio}:attack=#{attack}:release=#{release}:knee=#{knee}:makeup=#{makeup}"
      :limiter ->
        "alimiter=limit=#{params.threshold}dB"
      :expander ->
        "aexpand=threshold=#{params.threshold}dB:ratio=#{params.ratio}"
      :gate ->
        "agate=threshold=#{params.threshold}dB:ratio=#{params.ratio}:attack=#{params.attack}:release=#{params.release}"
      :multiband ->
        build_multiband_filter(params.bands)
      :parallel ->
        "[0:a]acompressor[compressed];[0:a]amerge=inputs=2[merged]"
      :sidechain ->
        "[0:a][1:a]sidechaincompress"
    end
  end

  defp build_multiband_filter(bands) do
    filters = bands |> Enum.with_index() |> Enum.map(fn {band, idx} ->
      bandpass = "bandpass=f=#{(band.freq_low + band.freq_high) / 2}:width_type=h:width=#{band.freq_high - band.freq_low}"
      compressor = "acompressor=threshold=#{band.threshold}dB:ratio=#{band.ratio}:attack=#{band.attack}:release=#{band.release}"
      "[0:a]#{bandpass},#{compressor}[band#{idx}]"
    end)
    mix_inputs = Enum.map(0..(length(bands)-1), &"[band#{&1}]") |> Enum.join("")
    mix_filter = "#{mix_inputs}amerge=inputs=#{length(bands)}[out]"
    Enum.join(filters ++ [mix_filter], ";")
  end

  defp analyze_dynamics_with_ffmpeg(temp_file) do
    {output, 0} = System.cmd("ffmpeg", [
      "-i", temp_file,
      "-af", "astats=metadata=1:reset=1",
      "-f", "null", "-"
    ], stderr_to_stdout: true)
    parse_dynamics_analysis(output)
  end

  defp parse_dynamics_analysis(output) do
    peak_match = Regex.run(~r/Peak level dB: ([-+]?\d*\.?\d+)/, output)
    rms_match = Regex.run(~r/RMS level dB: ([-+]?\d*\.?\d+)/, output)
    crest_match = Regex.run(~r/Crest factor: ([-+]?\d*\.?\d+)/, output)
    %{
      peak_level: parse_float(peak_match),
      rms_level: parse_float(rms_match),
      crest_factor: parse_float(crest_match),
      dynamic_range: calculate_dynamic_range(parse_float(peak_match), parse_float(rms_match))
    } |> then(&{:ok, &1})
  end

  defp suggest_compressor_params(analysis, opts) do
    base = %{
      threshold: cond do
        analysis.peak_level > -3.0 -> -6.0
        analysis.peak_level > -6.0 -> -12.0
        analysis.peak_level > -12.0 -> -18.0
        true -> -24.0
      end,
      ratio: cond do
        analysis.crest_factor > 20 -> 8.0
        analysis.crest_factor > 15 -> 6.0
        analysis.crest_factor > 10 -> 4.0
        analysis.crest_factor > 5 -> 2.5
        true -> 2.0
      end,
      attack: cond do
        analysis.dynamic_range > 30 -> 50
        analysis.dynamic_range > 20 -> 30
        true -> 20
      end
    }

    release = base.attack * 5

    %{
      threshold: Keyword.get(opts, :threshold, base.threshold),
      ratio: Keyword.get(opts, :ratio, base.ratio),
      attack: Keyword.get(opts, :attack, base.attack),
      release: Keyword.get(opts, :release, release),
      knee: Keyword.get(opts, :knee, 6.0),
      makeup_gain: Keyword.get(opts, :makeup_gain, -base.threshold * 0.5),
      lookahead: Keyword.get(opts, :lookahead, 0),
      auto_release: Keyword.get(opts, :auto_release, true),
      mix: Keyword.get(opts, :mix, 1.0)
    }
  end

  defp suggest_compressor_type(analysis) do
    cond do
      analysis.dynamic_range > 25 -> :multiband
      analysis.crest_factor > 15 -> :limiter
      analysis.rms_level < -30 -> :expander
      true -> :compressor
    end
  end

  defp validate_compressor_params(params) do
    %{
      type: Map.get(params, :type, :compressor),
      threshold: clamp(Map.get(params, :threshold, -20.0), -60.0, 0.0),
      ratio: max(Map.get(params, :ratio, 4.0), 1.0),
      attack: max(Map.get(params, :attack, 20), 0),
      release: max(Map.get(params, :release, 250), 0),
      knee: clamp(Map.get(params, :knee, 6.0), 0.0, 30.0),
      makeup_gain: Map.get(params, :makeup_gain, 0.0),
      lookahead: max(Map.get(params, :lookahead, 0), 0),
      auto_release: Map.get(params, :auto_release, true),
      mix: clamp(Map.get(params, :mix, 1.0), 0.0, 1.0)
    }
  end

  defp validate_multiband_bands(bands) do
    validated = Enum.map(bands, fn band ->
      %{
        freq_low: max(Map.get(band, :freq_low, 20), 20),
        freq_high: min(Map.get(band, :freq_high, 20000), 20000),
        threshold: clamp(Map.get(band, :threshold, -20.0), -60.0, 0.0),
        ratio: max(Map.get(band, :ratio, 4.0), 1.0),
        attack: max(Map.get(band, :attack, 20), 0),
        release: max(Map.get(band, :release, 200), 0),
        solo: Map.get(band, :solo, false),
        mute: Map.get(band, :mute, false)
      }
    end)
    {:ok, validated}
  end

  defp split_signal(audio_stream, ratio) when ratio >= 0 and ratio <= 1 do
    case is_pcm?(audio_stream) do
      false ->
        audio_data = convert_to_pcm(audio_stream)
        do_split_pcm(audio_data, ratio)
      true ->
        do_split_pcm(audio_stream, ratio)
    end
  end

  defp do_split_pcm(pcm_data, ratio) do
    info = get_pcm_info(pcm_data)
    sample_bytes = div(info.bit_depth, 8)
    frame_bytes = sample_bytes * info.channels
    total_frames = div(byte_size(pcm_data), frame_bytes)
    split_frames = round(total_frames * ratio)
    split_bytes = split_frames * frame_bytes
    {
      %{
        data: :binary.part(pcm_data, 0, split_bytes),
        format: info.format,
        sample_rate: info.sample_rate,
        channels: info.channels,
        bit_depth: info.bit_depth,
        frames: split_frames
      },
      %{
        data: :binary.part(pcm_data, split_bytes, byte_size(pcm_data) - split_bytes),
        format: info.format,
        sample_rate: info.sample_rate,
        channels: info.channels,
        bit_depth: info.bit_depth,
        frames: total_frames - split_frames
      }
    }
  end

  defp is_pcm?(data) do
    case data do
      <<0x52, 0x49, 0x46, 0x46, _::binary>> -> true
      _ -> false
    end
  end

  defp convert_to_pcm(data) do
    case detect_format(data) do
      :mp3 -> convert_mp3_to_pcm(data)
      :aac -> convert_aac_to_pcm(data)
      :flac -> convert_flac_to_pcm(data)
      :ogg -> convert_ogg_to_pcm(data)
      :wav -> data
      :unknown -> convert_ffmpeg_auto(data)
    end
  end

  defp detect_format(<<0x49, 0x44, 0x33, _::binary>>), do: :mp3
  defp detect_format(<<0xFF, 0xFB, _::binary>>), do: :mp3
  defp detect_format(<<0xFF, 0xF1, _::binary>>), do: :aac
  defp detect_format(<<0x66, 0x4C, 0x61, 0x43>>), do: :flac
  defp detect_format(<<0x4F, 0x67, 0x67, 0x53>>), do: :ogg
  defp detect_format(<<0x52, 0x49, 0x46, 0x46, rest::binary>> = data) do
    if byte_size(data) >= 44 and
      binary_part(data, 8, 4) == "WAVE" and
      binary_part(data, 40, 4) == "data" do
      if byte_size(rest) >= 8 do
        :wav
      else
        :unknown
      end
    else
      :unknown
    end
  end

  defp detect_format(_), do: :unknown

  defp convert_mp3_to_pcm(mp3_data) do
    with {:ok, pcm} <- run_ffmpeg(mp3_data, "mp3", "s16le", [
      "-acodec", "pcm_s16le",
      "-ar", "44100",
      "-ac", "2"
    ]) do
      pcm
    else
      {:error, reason} ->
        Logger.error("MP3 conversion failed: #{reason}")
        fallback_conversion(mp3_data)
    end
  end

  defp convert_aac_to_pcm(aac_data) do
    with {:ok, pcm} <- run_ffmpeg(aac_data, "aac", "s16le", [
      "-acodec", "pcm_s16le",
      "-ar", "44100",
      "-ac", "2"
    ]) do
      pcm
    else
      {:error, reason} ->
        Logger.error("AAC conversion failed: #{reason}")
        fallback_conversion(aac_data)
    end
  end

  defp convert_flac_to_pcm(flac_data) do
    with {:ok, pcm} <- run_ffmpeg(flac_data, "flac", "s24le", [
      "-acodec", "pcm_s24le",
      "-ar", "48000",
      "-ac", "2"
    ]) do
      pcm
    else
      {:error, reason} ->
        Logger.error("FLAC conversion failed: #{reason}")
        fallback_conversion(flac_data)
    end
  end

  defp convert_ogg_to_pcm(ogg_data) do
    with {:ok, pcm} <- run_ffmpeg(ogg_data, "ogg", "s16le", [
      "-acodec", "pcm_s16le",
      "-ar", "44100",
      "-ac", "2"
    ]) do
      pcm
    else
      {:error, reason} ->
        Logger.error("OGG conversion failed: #{reason}")
        fallback_conversion(ogg_data)
    end
  end

  defp convert_ffmpeg_auto(data) do
    formats = ["mp3", "aac", "flac", "ogg", "wav", "m4a", "opus"]
    result = Enum.find_value(formats, fn format ->
      case run_ffmpeg(data, format, "s16le", []) do
        {:ok, pcm} -> pcm
        _ -> nil
      end
    end)
    if result do
      result
    else
      Logger.error("Could not convert unknown format to PCM")
      fallback_conversion(data)
    end
  end

  defp run_ffmpeg(input_data, input_format, output_format, extra_args) do
    input_path = "/tmp/ffmpeg_input_#{:erlang.unique_integer()}.#{input_format}"
    output_path = "/tmp/ffmpeg_output_#{:erlang.unique_integer()}.#{output_format}"

    try do
      File.write!(input_path, input_data)
      args = [
        "-i", input_path,
        "-f", output_format,
        "-acodec", "pcm_s16le",
        "-ar", "44100",
        "-ac", "2",
        "-y"
      ] ++ extra_args ++ [output_path]

      case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
        {_output, 0} ->
          {:ok, File.read!(output_path)}

        {error, status} ->
          {:error, "FFmpeg error (status #{status}): #{String.slice(error, 0, 200)}"}
      end
    after
      File.rm(input_path)
      File.rm(output_path)
    end
  end

  defp fallback_conversion(data) do
    Logger.warning("FFmpeg not available, returning original data")
    data
  end

  defp get_pcm_info(data) when is_binary(data) do
    case data do
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
          1 -> :s16le
          3 -> :f32le
          _ -> :unknown
        end

        %{
          sample_rate: sample_rate,
          channels: channels,
          bit_depth: bits_per_sample,
          format: format
        }
      _ ->
        %{
          sample_rate: 48000,
          channels: 2,
          bit_depth: 32,
          format: :f32
        }
    end
  end

  defp get_pcm_info(%{data: data}) do
    get_pcm_info(data)
  end

  defp mix_signals(signal1, signal2, ratio) when ratio >= 0 and ratio <= 1 do
    pcm1 = extract_pcm(signal1)
    pcm2 = extract_pcm(signal2)
    info1 = get_pcm_info(signal1)
    info2 = get_pcm_info(signal2)

    target_sr = max(info1.sample_rate, info2.sample_rate)
    target_ch = max(info1.channels, info2.channels)
    target_bits = max(info1.bit_depth, info2.bit_depth)

    f32_1 = pcm_to_f32(pcm1, info1.format, target_sr, info1.sample_rate)
    f32_2 = pcm_to_f32(pcm2, info2.format, target_sr, info2.sample_rate)

    # Выравниваем длину
    max_len = max(length(f32_1), length(f32_2))
    f32_1 = pad_samples(f32_1, max_len)
    f32_2 = pad_samples(f32_2, max_len)

    mixed = Enum.zip(f32_1, f32_2) |> Enum.map(fn {s1, s2} ->
      s1 * (1 - ratio) + s2 * ratio
    end)

    mixed = Enum.map(mixed, &soft_clip/1)
    f32_to_pcm(mixed, target_bits)
  end

  defp pad_samples(samples, target_length) when length(samples) >= target_length do
    samples
  end

  defp pad_samples(samples, target_length) do
    samples ++ List.duplicate(0.0, target_length - length(samples))
  end

  defp soft_clip(sample) when sample > 0.95 do
    0.95 + (sample - 0.95) * 0.5
  end

  defp soft_clip(sample) when sample < -0.95 do
    -0.95 + (sample + 0.95) * 0.5
  end

  defp soft_clip(sample), do: sample

  defp pcm_to_f32(data, format, target_sr \\ 44100, orig_sr \\ 44100) do
    samples = case format do
      :u8 ->
        for <<byte::8 <- data>>, do: (byte - 128) / 128.0
      :s16le ->
        for <<sample::16-signed-little <- data>>, do: sample / 32768.0
      :s24le ->
        for <<b1::8, b2::8, b3::8 <- data>> do
          raw = b1 + b2 * 256 + b3 * 65536
          sample = if raw >= 0x800000, do: raw - 0x1000000, else: raw
          sample / 8388608.0
        end
      :s32le ->
        for <<sample::32-signed-little <- data>>, do: sample / 2147483648.0
      :f32le ->
        for <<sample::float-32-little <- data>>, do: sample
      _ ->
        for <<byte::8 <- data>>, do: byte / 128.0
    end

    if target_sr != orig_sr do
      resample_ratio = target_sr / orig_sr
      Enum.map(0..(round(length(samples) * resample_ratio) - 1), fn i ->
        idx = round(i / resample_ratio)
        if idx < length(samples), do: Enum.at(samples, idx), else: 0.0
      end)
    else
      samples
    end
  end

  defp f32_to_pcm(samples, bits) do
    case bits do
      16 ->
        for s <- samples, into: <<>> do
          val = round(s * 32767.0) |> clamp(-32768, 32767)
          <<val::signed-16-little>>
        end
      24 ->
        for s <- samples, into: <<>> do
          val = round(s * 8388607.0) |> clamp(-8388608, 8388607)
          <<val::signed-24-little>>
        end
      32 ->
        for s <- samples, into: <<>> do
          val = round(s * 2147483647.0) |> clamp(-2147483648, 2147483647)
          <<val::signed-32-little>>
        end
      _ ->
        for s <- samples, into: <<>> do
          val = round(s * 32767.0) |> clamp(-32768, 32767)
          <<val::signed-16-little>>
        end
    end
  end

  defp analyze_envelope(audio_stream) do
    pcm = extract_pcm(audio_stream)
    info = get_pcm_info(audio_stream)
    samples = pcm_to_f32(pcm, info.format)
    channel_samples = split_channels(samples, info.channels)
    envelopes = Enum.map(channel_samples, fn chan_samples ->
      analyze_channel_envelope(chan_samples, info.sample_rate)
    end)
    avg_envelope = average_envelopes(envelopes)

    peaks = find_peaks(avg_envelope.curve, avg_envelope.peak * 0.2)

    %{
      attack_samples: detect_attack_time(avg_envelope, info.sample_rate),
      release_samples: detect_release_time(avg_envelope, info.sample_rate),
      threshold: propose_threshold(avg_envelope),
      peak_level: avg_envelope.peak,
      rms_level: avg_envelope.rms,
      crest_factor: avg_envelope.peak / avg_envelope.rms,
      dynamic_range: avg_envelope.peak_db - avg_envelope.noise_floor_db,
      envelope_curve: avg_envelope.curve,
      transients: detect_transients(avg_envelope, info.sample_rate),
      peaks: peaks,
      peak_count: length(peaks)
    }
  end

  defp split_channels(samples, channels) do
    Enum.map(0..channels-1, fn ch ->
      Enum.take_every(Enum.drop(samples, ch), channels)
    end)
  end

  defp analyze_channel_envelope(samples, sr) do
    window_sizes = [0.01, 0.05, 0.1]

    envelopes = Enum.map(window_sizes, fn window_ms ->
      window = round(sr * window_ms / 1000)
      compute_rms_envelope(samples, window)
    end)

    peak = Enum.max(samples)
    peak_db = 20 * :math.log10(peak + 1.0e-10)
    rms = :math.sqrt(Enum.reduce(samples, 0, &(&2 + &1 * &1)) / length(samples))
    rms_db = 20 * :math.log10(rms + 1.0e-10)
    noise_floor = estimate_noise_floor(samples)
    noise_floor_db = 20 * :math.log10(noise_floor + 1.0e-10)

    %{
      curve: envelopes |> Enum.zip_with(&Enum.sum/1) |> Enum.map(&(&1 / 3)),
      peak: peak,
      peak_db: peak_db,
      rms: rms,
      rms_db: rms_db,
      noise_floor: noise_floor,
      noise_floor_db: noise_floor_db
    }
  end

  defp compute_rms_envelope(samples, window) when window <= 0 do
    List.duplicate(0.0, div(length(samples), 4))
  end

  defp compute_rms_envelope(samples, window) do
    step = max(1, div(window, 4))
    Enum.map(0..div(length(samples) - window, step), fn i ->
      start = i * step
      frame = Enum.slice(samples, start, window)
      :math.sqrt(Enum.reduce(frame, 0, &(&2 + &1 * &1)) / window)
    end)
  end

  defp estimate_noise_floor(samples) do
    sorted = Enum.sort(samples)
    threshold_idx = round(length(sorted) * 0.1)
    quiet_samples = Enum.take(sorted, threshold_idx)

    if quiet_samples == [] do
      0.001
    else
      Enum.sum(quiet_samples) / length(quiet_samples)
    end
  end

  defp average_envelopes(envelopes) do
    max_len = Enum.map(envelopes, &length(&1.curve)) |> Enum.max()
    curves = Enum.map(envelopes, fn env ->
      if length(env.curve) < max_len do
        env.curve ++ List.duplicate(Enum.at(env.curve, -1), max_len - length(env.curve))
      else
        env.curve
      end
    end)

    avg_curve = curves |> Enum.zip_with(&Enum.sum/1) |> Enum.map(&(&1 / length(envelopes)))

    %{
      curve: avg_curve,
      peak: Enum.map(envelopes, & &1.peak) |> Enum.max(),
      peak_db: Enum.map(envelopes, & &1.peak_db) |> Enum.max(),
      rms: Enum.map(envelopes, & &1.rms) |> Enum.sum() |> Kernel./(length(envelopes)),
      rms_db: envelopes |> Enum.map(& &1.rms_db) |> Enum.sum() |> Kernel./(length(envelopes)),
      noise_floor: Enum.map(envelopes, & &1.noise_floor) |> Enum.min(),
      noise_floor_db: Enum.map(envelopes, & &1.noise_floor_db) |> Enum.min()
    }
  end

  defp detect_attack_time(env, sr) do
    curve = env.curve
    diffs = Enum.chunk_every(curve, 2, 1) |> Enum.map(fn [a, b] -> (b - a) / a end)

    case Enum.max_by(diffs, fn d -> d end) do
      max_diff when max_diff > 0.5 ->
        idx = Enum.find_index(diffs, fn d -> d == max_diff end) || 0
        round(idx * sr / 1000)
      _ ->
        100
    end
  end

  defp detect_release_time(env, sr) do
    curve = env.curve
    peak = Enum.max(curve)
    threshold = peak * 0.2

    case Enum.find_index(Enum.reverse(curve), fn level -> level >= threshold end) do
      nil ->
        100
      last_idx ->
        (length(curve) - last_idx) / sr * 1000
    end
  end

  defp propose_threshold(env) do
    env.noise_floor_db + 6.0
  end

  defp find_peaks(curve, threshold \\ 0.1) do
    peaks = Enum.chunk_every(curve, 3, 1) |> Enum.with_index() |> Enum.filter(fn {chunk, idx} ->
        case chunk do
          [a, b, c] when b > a and b > c and b > threshold -> true
          _ -> false
        end
      end) |> Enum.map(fn {chunk, idx} -> idx end)

    max_val = Enum.max(curve)
    max_idx = Enum.find_index(curve, &(&1 == max_val))

    if max_idx in peaks do
      peaks
    else
      [max_idx | peaks] |> Enum.sort()
    end
  end

  defp detect_transients(env, sr) do
    curve = env.curve
    threshold = env.peak * 0.3
    Enum.with_index(curve)
    |> Enum.filter(fn {val, _} -> val > threshold end)
    |> Enum.map(fn {_, idx} -> idx / sr end)
  end

  defp parse_float([_, value]), do: String.to_float(value)
  defp parse_float(_), do: 0.0

  defp calculate_dynamic_range(peak, rms) do
    peak - rms
  end

  defp clamp(value, min, max) when value < min, do: min
  defp clamp(value, min, max) when value > max, do: max
  defp clamp(value, min, max), do: value

  defp log_compression_metrics(start_time, size, params, processor, result) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    success? = match?({:ok, _}, result)

    :telemetry.execute([:music_core, :effects, :compression], %{
      duration: duration_ms,
      size: size,
      success: if(success?, do: 1, else: 0),
      threshold: params.threshold,
      ratio: params.ratio
    }, %{
      processor: processor,
      type: params.type
    })
  end

  defp extract_pcm(%{data: data}), do: data
  defp extract_pcm(data) when is_binary(data), do: data
end
