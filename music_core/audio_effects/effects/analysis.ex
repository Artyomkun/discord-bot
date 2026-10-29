defmodule MusicCore.AudioEffects.Effects.Analysis do
  @moduledoc """
  Содержит все аналитические функции, выделенные из основного модуля.
  """
  @behaviour MusicCore.AudioEffects.Effect
  import MusicCore.AudioEffects.Effects.Effects, only: [
    extract_sample_rate: 1,
    extract_channels: 1,
    calculate_duration: 3,
    calculate_rms: 1,
    calculate_peak: 1,
    calculate_crest_factor: 1,
    calculate_dynamic_range: 1,
    calculate_spectral_centroid: 3,
    calculate_spectral_spread: 4,
    calculate_spectral_rolloff: 4,
    calculate_spectral_flatness: 1,
    calculate_spectral_crest: 1,
    calculate_spectral_slope: 3,
    analyze_frequency_bands: 3,
    detect_spectral_issues: 2,
    detect_spectral_peaks: 3,
    compute_phase: 3,
    analyze_phase_coherence: 2,
    analyze_stereo_phase: 1,
    compute_group_delay: 2,
    compute_instantaneous_frequency: 2,
    detect_phase_anomalies: 1,
    detect_phase_cancellation: 1,
    unwrap_phase: 1,
    spectrum_data: 2,
  ]

  # Константы
  @default_fft_size 2048
  @default_sample_rate 44100

  @doc """
  Извлекает метаданные из аудио.
  """
  def extract_metadata(audio_data) when is_map(audio_data) do
    sample_rate = extract_sample_rate(audio_data)
    channels = extract_channels(audio_data)

    %{
      sample_rate: sample_rate,
      channels: channels,
      duration: calculate_duration(audio_data, sample_rate, channels),
      format: Map.get(audio_data, :format, "unknown"),
      bit_depth: Map.get(audio_data, :bit_depth, 16)
    }
  end

  def extract_metadata(audio_data) do
    %{}
  end

  @doc """
  Полный анализ аудиоданных.
  """
  def analyze_audio(audio_data) when is_map(audio_data) do
    sample_rate = extract_sample_rate(audio_data)
    channels = extract_channels(audio_data)

    spectrum_result = analyze_spectrum(audio_data, sample_rate)
    fft_size = spectrum_result.fft_size
    spectrum = spectrum_result.full_spectrum

    if Enum.empty?(spectrum) do
      minimal_analysis(audio_data, sample_rate, channels)
    else
      rms = calculate_rms(audio_data)
      peak = calculate_peak(audio_data)
      crest_factor = calculate_crest_factor(audio_data)
      dynamic_range = calculate_dynamic_range(audio_data)
      duration = calculate_duration(audio_data, sample_rate, channels)
      centroid = calculate_spectral_centroid(spectrum, sample_rate, fft_size)
      spectral_features = %{
        centroid: centroid,
        spread: calculate_spectral_spread(spectrum, centroid, sample_rate, fft_size),
        rolloff_85: calculate_spectral_rolloff(spectrum, sample_rate, fft_size, 0.85),
        flatness: calculate_spectral_flatness(spectrum),
        crest: calculate_spectral_crest(spectrum),
        slope: calculate_spectral_slope(spectrum, sample_rate, fft_size)
      }

      phase_data = compute_phase(audio_data, fft_size, sample_rate)
      phase_features = analyze_phase_features(phase_data, sample_rate)

      bands = analyze_frequency_bands(spectrum, sample_rate, fft_size)
      issues = analyze_issues(spectrum, bands, phase_data)

      %{
        metadata: %{sample_rate: sample_rate, channels: channels, duration: duration},
        basic: %{rms: rms, peak: peak, crest_factor: crest_factor, dynamic_range: dynamic_range},
        spectral: spectral_features,
        phase: phase_features,
        issues: issues,
        raw: %{spectrum: spectrum, phase_data: phase_data, bands: bands}
      }
    end
  end

  def analyze_audio(audio_data) do
    %{}
  end

  @doc """
  Анализирует форму волны.
  """
  def analyze_waveform(audio_data) when is_map(audio_data) do
    %{
      rms: calculate_rms(audio_data),
      peak: calculate_peak(audio_data),
      crest_factor: calculate_crest_factor(audio_data),
      dynamic_range: calculate_dynamic_range(audio_data)
    }
  end

  def analyze_waveform(audio_data) do
    %{}
  end

  def analyze_spectrum(audio_data, sample_rate) do
    result = spectrum_data(audio_data, sample_rate)

    case result do
      %{fft_size: fft_size, full_spectrum: full_spectrum} when is_list(full_spectrum) and length(full_spectrum) > 0 ->
        fft_size = if fft_size > 0, do: fft_size, else: @default_fft_size
        full_spectrum = if is_list(full_spectrum), do: full_spectrum, else: []

        centroid = calculate_spectral_centroid(full_spectrum, sample_rate, fft_size)
        spread = calculate_spectral_spread(full_spectrum, centroid, sample_rate, fft_size)
        rolloff_85 = calculate_spectral_rolloff(full_spectrum, sample_rate, fft_size, 0.85)
        rolloff_90 = calculate_spectral_rolloff(full_spectrum, sample_rate, fft_size, 0.90)
        flatness = calculate_spectral_flatness(full_spectrum)
        crest = calculate_spectral_crest(full_spectrum)
        slope = calculate_spectral_slope(full_spectrum, sample_rate, fft_size)
        band_analysis = analyze_frequency_bands(full_spectrum, sample_rate, fft_size)
        issues = detect_spectral_issues(result, band_analysis)

        %{
          centroid: centroid,
          spread: spread,
          rolloff_85: rolloff_85,
          rolloff_90: rolloff_90,
          flatness: flatness,
          crest: crest,
          slope: slope,
          bands: band_analysis,
          issues: issues,
          spectrum_preview: Enum.take(full_spectrum, 20),
          fft_size: fft_size,
          full_spectrum: full_spectrum
        }

      _ ->
        %{
          centroid: 0.0,
          spread: 0.0,
          rolloff_85: 0.0,
          rolloff_90: 0.0,
          flatness: 0.0,
          crest: 0.0,
          slope: 0.0,
          bands: %{},
          issues: [],
          spectrum_preview: [],
          fft_size: @default_fft_size,
          full_spectrum: []
        }
    end
  end

  defp analyze_phase_features(phase_data, sample_rate) do
    if is_nil(phase_data) or Enum.empty?(phase_data) do
      %{
        coherence: 0.0,
        stereo_phase: 0.0,
        group_delay: 0.0,
        instant_freq: 0.0,
        anomalies: [],
        cancellation: false
      }
    else
      %{
        coherence: analyze_phase_coherence(phase_data, sample_rate),
        stereo_phase: analyze_stereo_phase(phase_data),
        group_delay: compute_group_delay(phase_data, sample_rate),
        instant_freq: compute_instantaneous_frequency(phase_data, sample_rate),
        anomalies: detect_phase_anomalies(phase_data),
        cancellation: detect_phase_cancellation(phase_data)
      }
    end
  end

  defp analyze_issues(spectrum, bands, phase_data) do
    %{
      spectral: detect_spectral_issues(spectrum, bands),
      phase: %{
        anomalies: detect_phase_anomalies(phase_data),
        cancellation: detect_phase_cancellation(phase_data)
      },
      peaks: detect_spectral_peaks(spectrum, 44100, length(spectrum) * 2)
    }
  end

  defp minimal_analysis(audio_data, sample_rate, channels) do
    duration = calculate_duration(audio_data, sample_rate, channels)
    rms = calculate_rms(audio_data)
    peak = calculate_peak(audio_data)

    %{
      metadata: %{sample_rate: sample_rate, channels: channels, duration: duration},
      basic: %{rms: rms, peak: peak, crest_factor: 0.0, dynamic_range: 0.0},
      spectral: %{
        centroid: 0.0,
        spread: 0.0,
        rolloff_85: 0.0,
        flatness: 0.0,
        crest: 0.0,
        slope: 0.0
      },
      phase: %{
        coherence: 0.0,
        stereo_phase: 0.0,
        group_delay: 0.0,
        instant_freq: 0.0,
        anomalies: [],
        cancellation: false
      },
      issues: %{
        spectral: [],
        phase: %{anomalies: [], cancellation: false},
        peaks: []
      },
      raw: %{spectrum: [], phase_data: [], bands: []}
    }
  end

  @doc """
  Анализирует динамику.
  """
  def analyze_dynamics(audio_data) when is_map(audio_data) do
    rms = calculate_rms(audio_data)
    peak = calculate_peak(audio_data)

    %{
      rms_db: db_from_linear(rms),
      peak_db: db_from_linear(peak),
      crest_factor: calculate_crest_factor(audio_data),
      dynamic_range: calculate_dynamic_range(audio_data),
      zero_crossing_rate: calculate_zero_crossing_rate(audio_data),
      energy: calculate_energy(audio_data)
    }
  end

  def analyze_dynamics(audio_data) do
    %{}
  end

  @doc """
  Анализирует пространственные характеристики.
  """
  def analyze_spatial(audio_data) when is_map(audio_data) do
    channels = extract_channels(audio_data)

    if channels == 2 do
      sample_rate = extract_sample_rate(audio_data)
      fft_size = Application.get_env(:music_core, :fft_size, @default_fft_size)
      phase_data = compute_phase(audio_data, fft_size, sample_rate)

      %{
        type: :stereo,
        phase_coherence: analyze_phase_coherence(phase_data, sample_rate),
        stereo_phase: analyze_stereo_phase(phase_data),
        group_delay: compute_group_delay(phase_data, sample_rate),
        instant_frequency: compute_instantaneous_frequency(phase_data, sample_rate),
        phase_anomalies: detect_phase_anomalies(phase_data),
        phase_cancellation: detect_phase_cancellation(phase_data)
      }
    else
      %{
        type: :mono,
        phase_coherence: 1.0,
        stereo_phase: 0.0,
        group_delay: 0.0,
        instant_frequency: 0.0,
        phase_anomalies: [],
        phase_cancellation: false
      }
    end
  end

  def analyze_spatial(audio_data) do
    %{type: :unknown}
  end

  @doc """
  Анализирует качество аудио.
  """
  def analyze_quality(audio_data) when is_map(audio_data) do
    sample_rate = extract_sample_rate(audio_data)
    spectrum_result = analyze_spectrum(audio_data, sample_rate)

    %{
      noise_floor: calculate_noise_floor(spectrum_result.full_spectrum),
      clipping: detect_clipping(spectrum_result.full_spectrum),
      bandwidth: calculate_bandwidth(spectrum_result),
      distortion: estimate_distortion(spectrum_result.full_spectrum)
    }
  end

  def analyze_quality(audio_data) do
    %{}
  end

  @doc """
  Генерирует человеко-читаемую сводку анализа.
  """
  def generate_summary(analysis) when is_map(analysis) do
    metadata = Map.get(analysis, :metadata, %{})
    basic = Map.get(analysis, :basic, %{})
    spectral = Map.get(analysis, :spectral, %{})
    phase = Map.get(analysis, :phase, %{})
    issues = Map.get(analysis, :issues, %{})
    spectral_issues = Map.get(issues, :spectral, [])

    """
    📊 Анализ аудио:
    ─────────────────
    📝 Метаданные: #{Map.get(metadata, :channels, 0)}ch, #{Map.get(metadata, :sample_rate, 0)}Hz, #{trunc(Map.get(metadata, :duration, 0))}s

    🔊 Динамика:
      • RMS: #{Float.round(Map.get(basic, :rms, 0) * 100, 1)}%
      • Пик: #{Float.round(Map.get(basic, :peak, 0) * 100, 1)}%
      • Крест-фактор: #{Float.round(Map.get(basic, :crest_factor, 0), 2)}

    🎵 Спектр:
      • Центроид: #{trunc(Map.get(spectral, :centroid, 0))} Hz
      • Распространение: #{trunc(Map.get(spectral, :spread, 0))} Hz
      • Роллофф: #{trunc(Map.get(spectral, :rolloff_85, 0))} Hz

    ⚠️ Проблемы:
      • Спектральные: #{length(spectral_issues)}
      • Фазовые: #{length(Map.get(phase, :anomalies, []))}
    """
  end

  def generate_summary(analysis) do
    "Нет данных для анализа"
  end

  # ========== Приватные функции ==========

  defp db_from_linear(0) do
    -1.0e308
  end

  defp db_from_linear(value) do
    20 * :math.log10(value)
  end

  defp calculate_zero_crossing_rate(samples) when is_list(samples) and length(samples) > 1 do
    crossings = samples
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.count(fn [a, b] -> a * b < 0 end)

    crossings / (length(samples) - 1)
  end

  defp calculate_zero_crossing_rate(samples) when is_list(samples) do
    0.0
  end

  defp calculate_zero_crossing_rate(audio_data) do
    0.0
  end

  defp calculate_energy(samples) when is_list(samples) do
    samples
    |> Enum.map(fn x -> x * x end)
    |> Enum.sum()
  end

  defp calculate_energy(samples) do
    0.0
  end

  defp calculate_noise_floor(spectrum) when is_list(spectrum) and length(spectrum) > 0 do
    spectrum
    |> Enum.sort()
    |> percentile(0.1)
  end

  defp calculate_noise_floor(spectrum) do
    0.0
  end

  defp detect_clipping(spectrum) when is_list(spectrum) and length(spectrum) > 0 do
    max_val = Enum.max(spectrum)
    threshold = max_val * 0.9
    clipped = Enum.count(spectrum, &(&1 > threshold))

    clipped / length(spectrum)
  end

  defp detect_clipping(spectrum) do
    0.0
  end

  defp calculate_bandwidth(%{full_spectrum: spectrum, fft_size: fft_size}) do
    calculate_bandwidth(spectrum, fft_size)
  end

  defp calculate_bandwidth(spectrum, fft_size) when is_list(spectrum) and length(spectrum) > 1 do
    max_val = Enum.max(spectrum)
    threshold = max_val * 0.707

    indices = spectrum
    |> Enum.with_index()
    |> Enum.filter(fn {val, _} -> val >= threshold end)
    |> Enum.map(fn {_, idx} -> idx end)

    if length(indices) >= 2 do
      List.last(indices) - List.first(indices)
    else
      0
    end
  end

  defp calculate_bandwidth(spectrum, fft_size) do
    0
  end

  defp estimate_distortion(spectrum) when is_list(spectrum) and length(spectrum) > 0 do
    fundamental = Enum.max(spectrum)
    harmonics = tl(spectrum) |> Enum.max(fn -> 0 end)

    if fundamental > 0 do
      harmonics / fundamental
    else
      0.0
    end
  end

  defp estimate_distortion(spectrum) do
    0.0
  end

  defp percentile(list, p) when is_list(list) and length(list) > 0 do
    sorted = Enum.sort(list)
    index = round(p * length(sorted))
    clamped_index = min(max(index, 0), length(sorted) - 1)
    Enum.at(sorted, clamped_index)
  end

  defp percentile(list, p) do
    0.0
  end
end
