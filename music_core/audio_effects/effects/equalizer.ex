defmodule MusicCore.AudioEffects.Effects.Equalizer do
  @moduledoc """
  Модуль для частотной коррекции аудио (эквалайзер).

  Особенности:
  - Графический и параметрический эквалайзеры
  - Поддержка стандартных частотных полос (ISO 266)
  - Многополосная обработка (до 31 полосы)
  - Линейная фаза (linear phase) и минимальная фаза (minimum phase)
  - Автоматическая калибровка по анализу спектра
  - Кэширование фильтров для производительности

  Поддерживает форматы:
  - Graphic EQ (фиксированные полосы)
  - Parametric EQ (частоты, Q, gain)
  - Shelving EQ (low/high shelf)
  - Notch filters
  """
  @behaviour MusicCore.AudioEffects.Effect
  require Logger
  alias MusicCore.AudioEffects.Native.DSP
  alias MusicCore.AudioEffects.FFmpegWrapper
  alias MusicCore.Services.GoProcessor

  import MusicCore.AudioEffects.Effects.EffectsManager, only: [
    calculate_q_factor: 2,
    find_spectral_peaks: 1
  ]

  @type eq_type ::
        :graphic |
        :parametric |
        :shelving |
        :linear_phase |
        :minimum_phase |
        :analog_model

  @type eq_band :: %{
    freq: float(),
    gain: float(),
    q: float(),
    type: :peaking | :low_shelf | :high_shelf | :notch | :band_pass | :high_pass | :low_pass
  }

  @type eq_preset :: %{
    type: eq_type,
    bands: list(eq_band()),
    sample_rate: integer(),
    preamp: float(),
    auto_gain: boolean(),
    normalize: boolean(),
    phase_correction: boolean()
  }

  @type frequency_band :: %{
    freq: float(),
    energy: float(),
    energy_db: float(),
    target: float(),
    deviation: float(),
    q_factor: float()
  }

  @type frequency_analysis :: %{
    bands: list(frequency_band()),
    overall_balance: map(),
    needs_correction: boolean(),
    recommendations: list(map()),
    peak_frequencies: list(float()),
    spectral_centroid: float(),
    spectral_rolloff: float(),
    dynamic_range: map(),
    confidence: float()
  }

  @standard_bands [
    20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630,
    800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000,
    12500, 16000, 20000
  ]

  @default_presets %{
    flat: %{
      type: :graphic,
      bands: Enum.map(@standard_bands, &%{freq: &1, gain: 0.0, q: 0.707, type: :peaking}),
      preamp: 0.0,
      auto_gain: false
    },
    bass_boost: %{
      type: :graphic,
      bands: [
        %{freq: 60, gain: 6.0, q: 0.8, type: :low_shelf},
        %{freq: 120, gain: 3.0, q: 1.0, type: :peaking},
        %{freq: 240, gain: 2.0, q: 1.2, type: :peaking}
      ],
      preamp: -2.0,
      auto_gain: true
    },
    vocal_boost: %{
      type: :parametric,
      bands: [
        %{freq: 1000, gain: 3.0, q: 1.2, type: :peaking},
        %{freq: 3000, gain: 2.0, q: 1.5, type: :peaking},
        %{freq: 5000, gain: 1.0, q: 2.0, type: :peaking}
      ],
      preamp: 0.0,
      auto_gain: false
    },
    treble_enhance: %{
      type: :shelving,
      bands: [
        %{freq: 8000, gain: 4.0, q: 0.707, type: :high_shelf},
        %{freq: 12000, gain: 2.0, q: 0.8, type: :peaking}
      ],
      preamp: 0.0,
      auto_gain: false
    },
    radio: %{
      type: :graphic,
      bands: [
        %{freq: 100, gain: 2.0, q: 1.0, type: :peaking},
        %{freq: 1000, gain: 1.0, q: 1.0, type: :peaking},
        %{freq: 5000, gain: 3.0, q: 1.0, type: :peaking},
        %{freq: 10000, gain: 2.0, q: 0.8, type: :high_shelf}
      ],
      preamp: 0.0,
      auto_gain: true
    },
    loudness: %{
      type: :graphic,
      bands: [
        %{freq: 60, gain: 8.0, q: 0.8, type: :low_shelf},
        %{freq: 10000, gain: 4.0, q: 0.7, type: :high_shelf}
      ],
      preamp: -4.0,
      auto_gain: true
    },
    mastering: %{
      type: :linear_phase,
      bands: [
        %{freq: 30, gain: -1.0, q: 0.5, type: :high_pass},
        %{freq: 60, gain: 1.0, q: 0.8, type: :low_shelf},
        %{freq: 200, gain: 0.5, q: 2.0, type: :peaking},
        %{freq: 8000, gain: -0.5, q: 1.5, type: :peaking},
        %{freq: 16000, gain: 0.5, q: 0.7, type: :high_shelf}
      ],
      preamp: 0.0,
      auto_gain: false,
      phase_correction: true
    },
    noise_reduction: %{
      type: :parametric,
      bands: [
        %{freq: 50, gain: -12.0, q: 0.5, type: :notch},
        %{freq: 100, gain: -6.0, q: 1.0, type: :notch},
        %{freq: 10000, gain: -3.0, q: 0.8, type: :high_shelf}
      ],
      preamp: 0.0,
      auto_gain: true
    },
    live: %{
      type: :graphic,
      bands: Enum.map(@standard_bands, fn freq ->
        gain = cond do
          freq < 80 -> 3.0
          freq < 200 -> 2.0
          freq > 8000 -> 2.0
          true -> 0.0
        end
        %{freq: freq, gain: gain, q: 0.707, type: :peaking}
      end),
      preamp: 0.0,
      auto_gain: false
    }
  }

  @impl true
  def apply(audio_stream, config, opts) do
    apply_equalizer(audio_stream, config, opts)
  end

  @doc """
  Основная функция применения эквалайзера.
  """
  @spec apply_equalizer(binary(), atom() | map() | keyword(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def apply_equalizer(audio_stream, config, opts \\ []) do
    start_time = System.monotonic_time()
    eq_config = get_eq_config(config, opts)
    processor = Keyword.get(opts, :processor, :auto)

    result = case processor do
      :ffmpeg -> apply_with_ffmpeg(audio_stream, eq_config, opts)
      :native -> apply_with_native(audio_stream, eq_config, opts)
      :go -> apply_with_go(audio_stream, eq_config, opts)
      :auto -> apply_auto(audio_stream, eq_config, opts)
    end

    log_eq_metrics(start_time, byte_size(audio_stream), eq_config, processor, result)
    result
  end

  @doc """
  Автоматическая коррекция частотного баланса на основе анализа.
  """
  @spec auto_equalize(binary(), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def auto_equalize(audio_stream, opts \\ []) do
    case analyze_frequency_spectrum(audio_stream) do
      {:ok, analysis} ->
        eq_config = generate_eq_from_analysis(analysis, opts)
        apply_equalizer(audio_stream, eq_config, opts)
      error ->
        error
    end
  end

  @doc """
  Многополосный эквалайзер (graphic EQ) с ISO стандартными полосами.
  """
  @spec graphic_eq(binary(), list(float()), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def graphic_eq(audio_stream, band_gains, opts \\ []) when is_list(band_gains) do
    bands = Enum.zip(@standard_bands, band_gains)
    |> Enum.map(fn {freq, gain} ->
      %{freq: freq, gain: gain, q: 0.707, type: :peaking}
    end)

    config = %{
      type: :graphic,
      bands: bands,
      preamp: calculate_preamp(band_gains),
      sample_rate: Keyword.get(opts, :sample_rate, 48000)
    }

    apply_equalizer(audio_stream, config, opts)
  end

  @doc """
  Параметрический эквалайзер с тонкой настройкой.
  """
  @spec parametric_eq(binary(), list(map()), keyword()) :: {:ok, binary()} | {:error, String.t()}
  def parametric_eq(audio_stream, bands, opts \\ []) when is_list(bands) do
    config = %{
      type: :parametric,
      bands: validate_parametric_bands(bands),
      preamp: Keyword.get(opts, :preamp, 0.0),
      phase_correction: Keyword.get(opts, :phase_correction, false)
    }

    apply_equalizer(audio_stream, config, opts)
  end

  @doc """
  Создание кастомного пресета эквалайзера.
  """
  @spec create_preset(atom(), map()) :: {:ok, atom(), map()}
  def create_preset(name, config) when is_map(config) do
    validated_config = validate_eq_config(config)

    case :ets.info(:eq_presets) do
      :undefined ->
        :ets.new(:eq_presets, [:named_table, :public, read_concurrency: true])
      _ ->
        :ok
    end

    :ets.insert(:eq_presets, {name, validated_config})
    {:ok, name, validated_config}
  end

  @doc """
  Получить список доступных пресетов.
  """
  @spec list_presets() :: list(atom())
  def list_presets do
    Map.keys(@default_presets)
  end

  @doc """
  Анализ частотного спектра аудио.
  Возвращает информацию об энергетическом балансе по полосам.
  """
  @spec analyze_frequency_spectrum(binary()) :: {:ok, frequency_analysis()} | {:error, atom()}
  def analyze_frequency_spectrum(audio_stream) do
    if System.find_executable("ffmpeg") do
      analyze_with_ffmpeg(audio_stream)
    else
      analyze_with_native(audio_stream)
    end
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp get_eq_config(preset_name, opts) when is_atom(preset_name) do
    case Map.get(@default_presets, preset_name) do
      nil ->
        Logger.warning("Unknown EQ preset: #{preset_name}, using :flat")
        @default_presets.flat

      base_config ->
        merge_with_opts(base_config, opts)
    end
  end

  defp get_eq_config(config, opts) when is_map(config) do
    merge_with_opts(config, opts)
  end

  defp get_eq_config(bands, opts) when is_list(bands) do
    %{
      type: :graphic,
      bands: bands,
      preamp: 0.0,
      sample_rate: 48000
    }
    |> merge_with_opts(opts)
  end

  defp merge_with_opts(base_config, opts) do
    base_config
    |> Map.merge(Map.new(opts))
    |> validate_eq_config()
  end

  defp apply_with_ffmpeg(audio_stream, config, opts) do
    try do
      filter = build_ffmpeg_filter(config)
      output_format = Keyword.get(opts, :output_format, :opus)
      bitrate = Keyword.get(opts, :bitrate, "128k")

      case FFmpegWrapper.process(audio_stream,
          filters: [filter],
          output_format: output_format,
          bitrate: bitrate) do
        {:ok, processed} -> {:ok, processed}
        error -> error
      end
    rescue
      error ->
        Logger.error("FFmpeg equalizer failed: #{inspect(error)}")
        {:error, "FFmpeg processing failed"}
    end
  end

  defp apply_with_native(audio_stream, config, opts) do
    try do
      case DSP.apply_equalizer(audio_stream, config) do
        {:ok, processed} -> {:ok, processed}
        {:error, reason} ->
          Logger.warning("Native DSP equalizer failed: #{reason}, falling back")
          if Keyword.get(opts, :fallback, true) do
            apply_with_ffmpeg(audio_stream, config, [])
          else
            {:error, reason}
          end
      end
    rescue
      error ->
        Logger.error("Native equalizer failed: #{inspect(error)}")
        {:error, "Native processing failed"}
    end
  end

  defp apply_with_go(audio_stream, config, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)

    case GoProcessor.apply_equalizer(audio_stream, config, timeout: timeout) do
      {:ok, processed} -> {:ok, processed}
      {:error, reason} ->
        Logger.warning("Go service equalizer failed: #{inspect(reason)}, falling back to native")
        apply_with_native(audio_stream, config, Keyword.put(opts, :fallback, true))
    end
  end

  defp apply_auto(audio_stream, config, opts) do
    audio_size = byte_size(audio_stream)

    cond do
      config.type in [:linear_phase, :analog_model] ->
        apply_with_ffmpeg(audio_stream, config, opts)
      length(config.bands) > 10 and audio_size > 1_000_000 ->
        apply_with_go(audio_stream, config, opts)
      Code.ensure_loaded?(DSP) ->
        apply_with_native(audio_stream, config, opts)
      true ->
        apply_with_ffmpeg(audio_stream, config, opts)
    end
  end

  defp build_ffmpeg_filter(config) do
    bands = config.bands

    filter_parts = Enum.map(bands, fn band ->
      case band.type do
        :low_shelf ->
          "equalizer=f=#{band.freq}:width_type=h:width=#{band.freq / 2}:g=#{band.gain}:t=0"
        :high_shelf ->
          "equalizer=f=#{band.freq}:width_type=h:width=#{band.freq / 2}:g=#{band.gain}:t=1"
        :peaking ->
          width = band.freq / band.q
          "equalizer=f=#{band.freq}:width_type=h:width=#{width}:g=#{band.gain}"
        :notch ->
          width = band.freq / band.q
          "equalizer=f=#{band.freq}:width_type=h:width=#{width}:g=#{band.gain}"
        :high_pass ->
          "highpass=f=#{band.freq}"
        :low_pass ->
          "lowpass=f=#{band.freq}"
        :band_pass ->
          "bandpass=f=#{band.freq}:width_type=h:width=#{band.freq / band.q}"
      end
    end)

    filter_parts = if config.preamp != 0.0 do
      ["volume=volume=#{db_to_linear(config.preamp)}" | filter_parts]
    else
      filter_parts
    end

    filter_parts
    |> Enum.reverse()
    |> Enum.join(",")
  end

  defp analyze_with_ffmpeg(audio_stream) do
    temp_file = Path.join(System.tmp_dir!(), "analyze_#{:erlang.unique_integer([:positive])}.opus")

    try do
      File.write!(temp_file, audio_stream)
      {output, 0} = System.cmd("ffmpeg", [
        "-i", temp_file,
        "-af", "showfreqs=mode=bar:ascale=lin:fscale=log:size=800x400",
        "-f", "null", "-"
      ], stderr_to_stdout: true)

      parse_frequency_analysis(output)
    rescue
      error ->
        Logger.error("Frequency analysis failed: #{inspect(error)}")
        {:error, :analysis_failed}
    after
      File.rm(temp_file)
    end
  end

  defp analyze_with_native(audio_stream) do
    case DSP.analyze_spectrum(audio_stream) do
      {:ok, analysis} -> {:ok, analysis}
      _ -> {:error, :native_analysis_failed}
    end
  end

  defp parse_frequency_analysis(output) do
    try do
      bands = parse_frequency_bands(output)

      analysis = %{
        bands: bands,
        overall_balance: calculate_balance(bands),
        needs_correction: needs_eq_correction(bands),
        recommendations: suggest_eq_corrections(bands),
        peak_frequencies: find_peak_frequencies(bands),
        spectral_centroid: calculate_spectral_centroid(bands),
        spectral_rolloff: calculate_spectral_rolloff(bands),
        dynamic_range: calculate_band_dynamics(bands),
        confidence: calculate_analysis_confidence(bands)
      }

      {:ok, analysis}
    rescue
      e ->
        Logger.error("Failed to parse frequency analysis: #{inspect(e)}")
        fallback_frequency_analysis()
    end
  end

  defp parse_frequency_bands(output) do
    lines = String.split(output, "\n")

    @standard_bands
    |> Enum.map(fn freq ->
      energy = extract_band_energy(lines, freq)
      energy_db = 20 * :math.log10(energy + 1.0e-10)
      target = calculate_target_level(freq)

      %{
        freq: freq,
        energy: energy,
        energy_db: energy_db,
        target: target,
        deviation: energy_db - target,
        q_factor: 1.0
      }
    end)
  end

  defp extract_band_energy(lines, target_freq) do
    found = Enum.find(lines, fn line ->
      case extract_freq_from_line(line) do
        {:ok, freq} -> abs(freq - target_freq) < target_freq * 0.1
        _ -> false
      end
    end)

    case found do
      nil -> 0.001
      line -> extract_energy_from_line(line)
    end
  end

  defp extract_freq_from_line(line) do
    case Regex.run(~r/freq[=:]\s*([\d.]+)/i, line) do
      [_, freq_str] -> {:ok, String.to_float(freq_str)}
      _ -> :error
    end
  end

  defp extract_energy_from_line(line) do
    case Regex.run(~r/(?:energy|magnitude|power)[=:]\s*([\d.-]+)/i, line) do
      [_, val_str] ->
        val = String.to_float(val_str)

        if String.contains?(line, "dB") do
          :math.pow(10, val / 20)
        else
          val
        end
      _ -> 0.001
    end
  end

  defp calculate_target_level(freq) do
    cond do
      freq < 60 -> -12.0
      freq < 250 -> -18.0
      freq < 500 -> -20.0
      freq < 2000 -> -22.0
      freq < 8000 -> -24.0
      true -> -30.0
    end
  end

  defp calculate_balance(bands) do
    low = Enum.filter(bands, fn b -> b.freq < 250 end)
    mid = Enum.filter(bands, fn b -> b.freq >= 250 and b.freq < 4000 end)
    high = Enum.filter(bands, fn b -> b.freq >= 4000 end)

    low_avg = avg_energy(low)
    mid_avg = avg_energy(mid)
    high_avg = avg_energy(high)

    low_sum = Enum.sum(Enum.map(low, & &1.energy))
    mid_sum = Enum.sum(Enum.map(mid, & &1.energy))
    high_sum = Enum.sum(Enum.map(high, & &1.energy))

    %{
      low: low_avg,
      mid: mid_avg,
      high: high_avg,
      low_sum: low_sum,
      mid_sum: mid_sum,
      high_sum: high_sum,
      low_mid_ratio: if(mid_avg > 0, do: low_avg / mid_avg, else: 1.0),
      mid_high_ratio: if(high_avg > 0, do: mid_avg / high_avg, else: 1.0),
      low_high_ratio: if(high_avg > 0, do: low_avg / high_avg, else: 1.0)
    }
  end

  defp avg_energy([]), do: 0.0
  defp avg_energy(bands) do
    Enum.sum(Enum.map(bands, & &1.energy)) / length(bands)
  end

  defp find_peak_frequencies(bands) do
    bands
    |> Enum.filter(fn band -> band.energy_db > -15.0 end)
    |> Enum.sort_by(fn band -> band.energy_db end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn band -> band.freq end)
  end

  defp calculate_spectral_centroid(bands) do
    total_energy = Enum.sum(Enum.map(bands, & &1.energy))

    if total_energy > 0 do
      weighted_sum = Enum.reduce(bands, 0, fn band, acc ->
        acc + band.freq * band.energy
      end)
      weighted_sum / total_energy
    else
      1000.0
    end
  end

  defp calculate_spectral_rolloff(bands) do
    total_energy = Enum.sum(Enum.map(bands, & &1.energy))
    threshold = total_energy * 0.85

    Enum.reduce_while(bands, 0, fn band, acc ->
      new_acc = acc + band.energy

      if new_acc >= threshold do
        {:halt, band.freq}
      else
        {:cont, new_acc}
      end
    end)
  end

  defp calculate_band_dynamics(bands) do
    energies = Enum.map(bands, & &1.energy_db)

    %{
      min: Enum.min(energies),
      max: Enum.max(energies),
      range: Enum.max(energies) - Enum.min(energies),
      std_dev: calculate_std_dev(energies)
    }
  end

  defp calculate_std_dev(values) do
    mean = Enum.sum(values) / length(values)
    variance = Enum.reduce(values, 0, fn x, acc ->
      acc + (x - mean) * (x - mean)
    end) / length(values)

    :math.sqrt(variance)
  end

  defp needs_eq_correction(bands, opts \\ []) do
    deviation_weight = Keyword.get(opts, :deviation_weight, 0.6)
    balance_weight = Keyword.get(opts, :balance_weight, 0.4)
    threshold = Keyword.get(opts, :threshold, 0.7)

    deviation_score = calculate_deviation_score(bands)
    balance_score = calculate_balance_score(bands)
    total_score = deviation_score * deviation_weight + balance_score * balance_weight

    total_score > threshold
  end

  defp calculate_deviation_score(bands) do
    deviations = Enum.map(bands, fn band -> abs(band.deviation) end)
    avg_deviation = Enum.sum(deviations) / length(deviations)
    min(avg_deviation / 12.0, 1.0)
  end

  defp calculate_balance_score(bands) do
    balance = calculate_balance(bands)

    max_diff = [
      abs(balance.low - balance.mid),
      abs(balance.mid - balance.high),
      abs(balance.low - balance.high)
    ]
    |> Enum.max()

    min(max_diff / 12.0, 1.0)
  end

  defp suggest_eq_corrections(bands, mode \\ :detailed)

  defp suggest_eq_corrections(bands, :detailed) do
    bands
    |> Enum.filter(fn band -> abs(band.deviation) > 3.0 end)
    |> Enum.map(fn band ->
      correction = -band.deviation |> clamp(-6.0, 6.0)

      %{
        freq: band.freq,
        current: band.energy_db,
        target: band.energy_db + correction,
        correction: correction,
        q: band.q_factor,
        priority: abs(band.deviation) / 10.0,
        type: if(correction > 0, do: :boost, else: :cut),
        description: if(correction > 0, do: "Boost", else: "Cut") <> " #{band.freq}Hz by #{abs(correction)}dB"
      }
    end)
    |> Enum.sort_by(fn rec -> rec.priority end, :desc)
  end

  defp suggest_eq_corrections(bands, :simple) do
    balance = calculate_balance(bands)
    avg = (balance.low + balance.mid + balance.high) / 3.0

    suggestions = []

    suggestions = if balance.low < avg - 3.0 do
      diff = avg - balance.low
      [%{
        range: :bass,
        correction: round(diff),
        description: "Boost bass frequencies by #{round(diff)}dB",
        type: :boost,
        priority: diff / 10.0
      } | suggestions]
    else
      suggestions
    end

    suggestions = if balance.mid < avg - 3.0 do
      diff = avg - balance.mid
      [%{
        range: :mid,
        correction: round(diff),
        description: "Boost mid frequencies by #{round(diff)}dB",
        type: :boost,
        priority: diff / 10.0
      } | suggestions]
    else
      suggestions
    end

    suggestions = if balance.high < avg - 3.0 do
      diff = avg - balance.high
      [%{
        range: :treble,
        correction: round(diff),
        description: "Boost treble frequencies by #{round(diff)}dB",
        type: :boost,
        priority: diff / 10.0
      } | suggestions]
    else
      suggestions
    end

    suggestions
    |> Enum.sort_by(fn rec -> rec.priority end, :desc)
  end

  defp calculate_analysis_confidence(bands) do
    data_points = length(bands)

    cond do
      data_points < 3 -> 0.3
      data_points < 6 -> 0.6
      data_points < 10 -> 0.8
      true -> 0.95
    end
  end

  defp fallback_frequency_analysis do
    Logger.warning("Using fallback frequency analysis")

    bands = @standard_bands
    |> Enum.map(fn freq ->
      energy_db = -20.0
      energy = :math.pow(10, energy_db / 20)

      %{
        freq: freq,
        energy: energy,
        energy_db: energy_db,
        target: calculate_target_level(freq),
        deviation: energy_db - calculate_target_level(freq),
        q_factor: 1.0
      }
    end)

    {:ok, %{
      bands: bands,
      overall_balance: calculate_balance(bands),
      needs_correction: needs_eq_correction(bands),
      recommendations: suggest_eq_corrections(bands),
      peak_frequencies: [],
      spectral_centroid: 1000.0,
      spectral_rolloff: 8000.0,
      dynamic_range: %{min: -30.0, max: -15.0, range: 15.0, std_dev: 5.0},
      confidence: 0.3
    }}
  end

  defp generate_eq_from_analysis(analysis, opts) do
    peaks = find_spectral_peaks(analysis)

    bands = Enum.map(peaks, fn {freq, mag} ->
      q_factor = calculate_q_factor(analysis, freq)

      %{
        frequency: freq,
        gain: -mag,
        q: q_factor,
        filter_type: :peak,
        enabled: true
      }
    end)

    bands = add_shelf_bands(bands, analysis, opts)

    %{
      bands: bands,
      preamp: Keyword.get(opts, :preamp, 0.0),
      phase_linear: Keyword.get(opts, :phase_linear, false)
    }
  end

  defp add_shelf_bands(bands, analysis, opts) do
    low_threshold = Keyword.get(opts, :low_shelf_threshold, 100)
    high_threshold = Keyword.get(opts, :high_shelf_threshold, 12000)

    low_freq_issue = get_low_freq_issue(analysis, low_threshold)
    high_freq_issue = get_high_freq_issue(analysis, high_threshold)

    bands = if low_freq_issue do
      [%{
        frequency: 80,
        gain: low_freq_issue.gain * 6,
        q: 0.7,
        filter_type: :low_shelf,
        enabled: true
      } | bands]
    else
      bands
    end

    if high_freq_issue do
      [%{
        frequency: 12000,
        gain: high_freq_issue.gain * 6,
        q: 0.7,
        filter_type: :high_shelf,
        enabled: true
      } | bands]
    else
      bands
    end
  end

  defp get_low_freq_issue(analysis, threshold) do
    low_freqs = Enum.filter(analysis.bands, fn band -> band.freq < threshold end)

    if low_freqs == [] do
      nil
    else
      avg_low = Enum.reduce(low_freqs, 0, fn band, acc -> acc + band.energy_db end) / length(low_freqs)

      if avg_low > -15.0 do
        %{gain: -(avg_low + 15.0) / 10.0}
      else
        nil
      end
    end
  end

  defp get_high_freq_issue(analysis, threshold) do
    high_freqs = Enum.filter(analysis.bands, fn band -> band.freq > threshold end)

    if high_freqs == [] do
      nil
    else
      avg_high = Enum.reduce(high_freqs, 0, fn band, acc -> acc + band.energy_db end) / length(high_freqs)

      if avg_high > -25.0 do
        %{gain: -(avg_high + 25.0) / 10.0}
      else
        nil
      end
    end
  end

  defp validate_eq_config(config) do
    %{
      type: Map.get(config, :type, :graphic),
      bands: validate_eq_bands(Map.get(config, :bands, [])),
      preamp: clamp(Map.get(config, :preamp, 0.0), -12.0, 12.0),
      sample_rate: Map.get(config, :sample_rate, 48000),
      auto_gain: Map.get(config, :auto_gain, false),
      phase_correction: Map.get(config, :phase_correction, false),
      normalize: Map.get(config, :normalize, false)
    }
  end

  defp validate_eq_bands(bands) when is_list(bands) do
    Enum.map(bands, fn band ->
      %{
        freq: clamp(band.freq, 20.0, 20000.0),
        gain: clamp(Map.get(band, :gain, 0.0), -24.0, 24.0),
        q: max(Map.get(band, :q, 0.707), 0.1),
        type: Map.get(band, :type, :peaking)
      }
    end)
  end

  defp validate_parametric_bands(bands) do
    Enum.map(bands, fn band ->
      %{
        freq: band.freq,
        gain: Map.get(band, :gain, 0.0),
        q: Map.get(band, :q, 1.0),
        type: Map.get(band, :type, :peaking)
      }
    end)
  end

  defp calculate_preamp(band_gains) do
    max_gain = Enum.max(band_gains)

    if max_gain > 6.0 do
      -max_gain * 0.5
    else
      0.0
    end
  end

  defp db_to_linear(db) do
    :math.pow(10, db / 20)
  end

  defp clamp(value, min, max) when value < min, do: min
  defp clamp(value, min, max) when value > max, do: max
  defp clamp(value, _, _), do: value

  defp log_eq_metrics(start_time, size, config, processor, result) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    success? = match?({:ok, _}, result)
    bands_count = length(config.bands)
    total_gain = Enum.reduce(config.bands, 0.0, fn band, acc -> acc + band.gain end)

    :telemetry.execute([:music_core, :effects, :equalizer], %{
      duration: duration_ms,
      size: size,
      success: if(success?, do: 1, else: 0),
      bands_count: bands_count,
      total_gain: total_gain
    }, %{
      processor: processor,
      type: config.type
    })
  end
end
