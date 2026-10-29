defmodule MusicCore.AudioEffects.Effects.Effects do
  @moduledoc """
  Главный модуль для применения аудио эффектов.

  Координирует работу всех эффектов, обеспечивает:
  - Конвейерную обработку с оптимальным порядком
  - Интеллектуальное применение эффектов на основе анализа
  - Кэширование результатов
  - Мониторинг производительности
  - Fallback механизмы при ошибках

  Порядок эффектов:
  1. Normalizer
  2. Equalizer
  3. Compressor
  4. Reverb
  5. Limiter
  """
  @behaviour MusicCore.AudioEffects.Effect
  alias MusicCore.AudioEffects.Effects.{
    Normalizer,
    Equalizer,
    Compressor,
    Reverb,
    CacheManager
  }

  require Logger

  @type effects_config :: %{
    optional(:normalize) => boolean() | keyword(),
    optional(:equalizer) => map() | atom(),
    optional(:compressor) => map() | atom(),
    optional(:reverb) => map() | atom(),
    optional(:limiter) => map() | boolean(),
    optional(:preset) => atom(),
    optional(:order) => list(atom()),
    optional(:cache) => boolean(),
    optional(:processor) => atom()
  }

  @type processing_result :: %{
    audio: binary(),
    metadata: %{
      processing_time: integer(),
      applied_effects: list(atom()),
      cache_hit: boolean(),
      analysis: map() | nil,
      warnings: list(String.t())
    }
  }

  @default_pipeline_order [:normalize, :equalizer, :compressor, :reverb, :limiter]

  @default_presets %{
    music_mastering: %{
      normalize: [preset: :music],
      equalizer: :mastering,
      compressor: :transparent,
      limiter: true,
      order: [:normalize, :equalizer, :compressor, :limiter]
    },
    vocal_enhance: %{
      normalize: [preset: :speech],
      equalizer: :vocal_boost,
      compressor: :vocal,
      reverb: :room,
      limiter: true
    },
    bass_boost: %{
      normalize: true,
      equalizer: :bass_boost,
      compressor: :bass,
      limiter: true
    },
    radio_ready: %{
      normalize: [target_lufs: -10, max_true_peak: -2.0],
      equalizer: :radio,
      compressor: :aggressive,
      limiter: [threshold: -1.0],
      order: [:compressor, :equalizer, :normalize, :limiter]
    },
    streaming_optimized: %{
      normalize: [preset: :streaming],
      equalizer: :flat,
      compressor: :transparent,
      limiter: [threshold: -1.5],
      cache: true
    },
    transparent: %{
      normalize: true,
      limiter: true
    },
    live_performance: %{
      normalize: [preset: :music],
      compressor: :aggressive,
      limiter: [threshold: -0.5],
      order: [:compressor, :normalize, :limiter]
    }
  }

  @doc """
  Основная функция применения эффектов к аудио.
  """
  @spec apply_effects(binary(), atom() | effects_config(), keyword()) :: {:ok, processing_result()} | {:error, String.t()}
  def apply_effects(audio_stream, config, opts \\ []) do
    start_time = System.monotonic_time()
    full_config = get_full_config(config, opts)

    cached_result = if full_config[:cache] do
      check_cache(audio_stream, full_config)
    else
      nil
    end

    case cached_result do
      {:ok, cached} ->
        Logger.debug("Cache hit for effects processing")
        {:ok, build_result(cached, true, start_time, full_config)}

      nil ->
        process_effects(audio_stream, full_config, start_time, opts)
    end
  end

  @doc """
  Пакетная обработка нескольких аудио потоков.
  """
  @spec apply_effects_batch(list(binary()), atom() | effects_config(), keyword()) ::
          {:ok, list(processing_result())} | {:error, String.t()}
  def apply_effects_batch([], config, opts), do: {:ok, []}

  def apply_effects_batch(audio_streams, config, opts \\ []) when is_list(audio_streams) do
    Logger.info("Processing batch of #{length(audio_streams)} audio streams")

    full_config = get_full_config(config, opts)
    max_concurrent = Keyword.get(opts, :max_concurrent,
      Application.get_env(:music_core, :audio_processing, [])[:max_concurrent_streams] || 5)

    results = audio_streams
    |> Enum.map(&Task.async(fn -> apply_effects(&1, full_config, opts) end))
    |> Task.await_many(Keyword.get(opts, :timeout, 30000))

    aggregate_batch_results(results)
  end

  @doc """
  Интеллектуальное применение эффектов с автоматическим анализом.
  """
  @spec apply_effects_auto(binary(), keyword()) :: {:ok, processing_result()} | {:error, String.t()}
  def apply_effects_auto(audio_stream, opts \\ []) do
    case Normalizer.analyze_audio(audio_stream) do
      {:ok, analysis} ->
        suggested_config = suggest_effects_config(analysis, opts)
        apply_effects(audio_stream, suggested_config, Keyword.put(opts, :analysis, analysis))

      error ->
        error
    end
  end

  @doc """
  Применяет эффекты в реальном времени (low latency).
  """
  @spec apply_effects_realtime(binary(), keyword()) :: {:ok, processing_result()} | {:error, String.t()}
  def apply_effects_realtime(audio_stream, opts \\ []) do
    realtime_config = %{
      normalize: [preset: :music, processor: :native],
      compressor: [preset: :aggressive, attack: 5, release: 50],
      limiter: [threshold: -1.0, lookahead: 5]
    }

    apply_effects(audio_stream, realtime_config, Keyword.put(opts, :realtime, true))
  end

  @doc """
  Получить рекомендованную конфигурацию эффектов для аудио.
  """
  @spec suggest_effects(binary()) :: effects_config()
  def suggest_effects(audio_stream) do
    case Normalizer.analyze_audio(audio_stream) do
      {:ok, analysis} ->
        suggest_effects_config(analysis, [])
      _ ->
        @default_presets.transparent
    end
  end

  @doc """
  Создание кастомного пресета эффектов.
  """
  @spec create_preset(atom(), map()) :: {:ok, atom(), map()}
  def create_preset(name, config) when is_map(config) do
    case :ets.info(:audio_effects_presets) do
      :undefined ->
        :ets.new(:audio_effects_presets, [:named_table, :public, read_concurrency: true])
      _ ->
        :ok
    end

    :ets.insert(:audio_effects_presets, {name, config})
    {:ok, name, config}
  end

  @doc """
  Получить список доступных пресетов.
  """
  @spec list_presets() :: list(atom())
  def list_presets do
    Map.keys(@default_presets)
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp get_full_config(preset_name, opts) when is_atom(preset_name) do
    case Map.get(@default_presets, preset_name) do
      nil ->
        Logger.warning("Unknown effects preset: #{preset_name}, using :transparent")
        @default_presets.transparent

      base_config ->
        merge_with_opts(base_config, opts)
    end
  end

  defp get_full_config(config, opts) when is_map(config) do
    validate_effects_config(config)
  end

  defp merge_with_opts(base_config, opts) do
    config = Enum.reduce(opts, base_config, fn
      {:cache, value}, acc -> Map.put(acc, :cache, value)
      {:processor, value}, acc -> Map.put(acc, :processor, value)
      {:order, value}, acc when is_list(value) -> Map.put(acc, :order, value)
      {:strict, value}, acc -> Map.put(acc, :strict, value)
      {_, _}, acc -> acc
    end)

    if Map.has_key?(config, :order) do
      config
    else
      Map.put(config, :order, @default_pipeline_order)
    end
    |> validate_effects_config()
  end

  defp process_effects(audio_stream, config, start_time, opts) do
    Logger.debug("Processing audio with effects: #{inspect(Map.keys(config))}")

    metadata = %{
      original_size: byte_size(audio_stream),
      warnings: [],
      applied_effects: []
    }

    try do
      {result_audio, final_metadata} = Enum.reduce_while(config.order, {:ok, audio_stream, metadata}, fn
        effect, {:ok, current_audio, meta} ->
          case apply_single_effect(effect, current_audio, config, meta, opts) do
            {:ok, new_audio, new_meta} ->
              {:cont, {:ok, new_audio, new_meta}}
            {:skip, new_audio, new_meta} ->
              {:cont, {:ok, new_audio, new_meta}}
            {:error, reason, new_meta} ->
              if config[:strict] do
                {:halt, {:error, reason, new_meta}}
              else
                Logger.warning("Skipping effect #{effect}: #{reason}")
                {:cont, {:ok, current_audio, new_meta}}
              end
          end
        _, error ->
          {:halt, error}
      end)

      case result_audio do
        {:ok, processed, final_meta} ->
          if config[:cache] do
            save_to_cache(audio_stream, config, processed)
          end

          result = build_result(processed, false, start_time, config)
          {:ok, result}

        {:error, reason, meta} ->
          Logger.error("Effects processing failed: #{inspect(reason)}")
          {:error, to_string(reason)}
      end

    rescue
      error ->
        Logger.error("Effects processing crashed: #{inspect(error)}")
        {:error, "Processing failed: #{inspect(error)}"}
    end
  end

  defp apply_single_effect(effect, audio, config, metadata, opts) do
    effect_start = System.monotonic_time()

    result = case effect do
      :normalize -> apply_normalize(audio, config[:normalize], opts)
      :equalizer -> apply_equalizer(audio, config[:equalizer], opts)
      :compressor -> apply_compressor(audio, config[:compressor], opts)
      :reverb -> apply_reverb(audio, config[:reverb], opts)
      :limiter -> apply_limiter(audio, config[:limiter], opts)
      _ -> {:error, "Unknown effect: #{effect}"}
    end

    duration = System.monotonic_time() - effect_start
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    case result do
      {:ok, processed_audio} ->
        new_meta = %{metadata |
          applied_effects: [{effect, duration_ms} | metadata.applied_effects]
        }
        {:ok, processed_audio, new_meta}

      {:error, reason} ->
        new_meta = %{metadata |
          warnings: ["Skipped #{effect}: #{reason}" | metadata.warnings]
        }
        {:skip, audio, new_meta}
    end
  end

  # ========== ФУНКЦИИ ПРИМЕНЕНИЯ ЭФФЕКТОВ ==========

  defp apply_normalize(audio, nil, opts), do: {:ok, audio}
  defp apply_normalize(audio, false, opts), do: {:ok, audio}
  defp apply_normalize(audio, true, opts), do: Normalizer.normalize(audio, :streaming, opts)
  defp apply_normalize(audio, preset, opts) when is_atom(preset), do: Normalizer.normalize(audio, preset, opts)
  defp apply_normalize(audio, params, opts) when is_list(params), do: Normalizer.normalize(audio, params, opts)

  defp apply_equalizer(audio, nil, opts), do: {:ok, audio}
  defp apply_equalizer(audio, preset, opts) when is_atom(preset), do: Equalizer.apply_equalizer(audio, preset, opts)
  defp apply_equalizer(audio, params, opts) when is_map(params), do: Equalizer.apply_equalizer(audio, params, opts)

  defp apply_compressor(audio, nil, opts), do: {:ok, audio}
  defp apply_compressor(audio, preset, opts) when is_atom(preset), do: Compressor.compress(audio, preset, opts)
  defp apply_compressor(audio, params, opts) when is_map(params), do: Compressor.compress(audio, params, opts)

  defp apply_reverb(audio, nil, opts), do: {:ok, audio}
  defp apply_reverb(audio, preset, opts) when is_atom(preset), do: Reverb.add(audio, preset, opts)
  defp apply_reverb(audio, params, opts) when is_map(params), do: Reverb.add(audio, params, opts)

  defp apply_limiter(audio, nil, opts), do: {:ok, audio}
  defp apply_limiter(audio, false, opts), do: {:ok, audio}
  defp apply_limiter(audio, true, opts), do: Compressor.limit(audio, -1.5, opts)
  defp apply_limiter(audio, params, opts) when is_map(params) do
    threshold = Map.get(params, :threshold, -1.5)
    Compressor.limit(audio, threshold, opts)
  end

  # ========== КЭШИРОВАНИЕ ==========
  defp check_cache(audio_stream, config) do
    cache_key = generate_cache_key(audio_stream, config)

    case CacheManager.get(cache_key) do
      {:ok, cached} -> {:ok, cached}
      _ -> nil
    end
  end

  defp save_to_cache(audio_stream, config, processed_audio) do
    cache_key = generate_cache_key(audio_stream, config)
    ttl = Application.get_env(:music_core, :audio_processing, [])[:cache_ttl] || 3600
    CacheManager.put(cache_key, processed_audio, ttl: ttl)
  end

  defp generate_cache_key(audio_stream, config) do
    audio_hash = :crypto.hash(:sha256, audio_stream) |> Base.encode64(case: :lower)
    config_hash = :crypto.hash(:sha256, Jason.encode!(config)) |> Base.encode64(case: :lower)
    "effects:#{audio_hash}:#{config_hash}"
  end

  # ========== АНАЛИТИЧЕСКИЕ ФУНКЦИИ ==========

  def extract_sample_rate(audio_data) do
    case audio_data do
      <<0x52, 0x49, 0x46, 0x46, _::binary-size(4),
        0x57, 0x41, 0x56, 0x45,
        0x66, 0x6D, 0x74, 0x20, _::binary-size(4),
        0x01, 0x00, channels::little-16,
        sample_rate::little-32, _::binary>> ->
        sample_rate
      _ ->
        44100
    end
  end

  def extract_channels(audio_data) do
    case audio_data do
      <<0x52, 0x49, 0x46, 0x46, _::binary-size(4),
        0x57, 0x41, 0x56, 0x45,
        0x66, 0x6D, 0x74, 0x20, _::binary-size(4),
        0x01, 0x00, channels::little-16, _::binary>> ->
        channels
      _ ->
        2
    end
  end

  def calculate_duration(audio_data, sample_rate, channels) do
    data_size = byte_size(audio_data) - 44
    bytes_per_sample = 2
    samples = max(1, data_size / (bytes_per_sample * channels))
    samples / sample_rate
  end

  def calculate_rms(audio_data) do
    try do
      data = binary_part(audio_data, 44, byte_size(audio_data) - 44)
      samples = for <<sample::little-16 <- data>>, do: sample / 32768.0
      sum_squares = Enum.reduce(samples, 0, fn x, acc -> acc + x*x end)
      :math.sqrt(sum_squares / max(1, length(samples)))
    rescue
      _ -> 0.0
    end
  end

  def calculate_peak(audio_data) do
    try do
      data = binary_part(audio_data, 44, byte_size(audio_data) - 44)
      samples = for <<sample::little-16 <- data>>, do: abs(sample) / 32768.0
      Enum.max(samples)
    rescue
      _ -> 0.0
    end
  end

  def calculate_crest_factor(audio_data) do
    peak = calculate_peak(audio_data)
    rms = calculate_rms(audio_data)
    if rms > 1.0e-10, do: peak / rms, else: 1.0
  end

  def calculate_dynamic_range(audio_data) do
    peak_db = 20 * :math.log10(calculate_peak(audio_data) + 1.0e-10)
    rms_db = 20 * :math.log10(calculate_rms(audio_data) + 1.0e-10)
    peak_db - rms_db
  end

  def spectrum_data(audio_data, sample_rate) do
    samples = extract_samples(audio_data)

    if length(samples) < 64 do
      %{
        full_spectrum: [],
        magnitude_db: [],
        phase: %{},
        bands: %{},
        features: %{},
        peaks: [],
        fft_size: 512,
        sample_rate: sample_rate,
        num_frames: 0,
        hop_size: 128,
        window_type: :hann,
        calibration_factor: 0.0,
        low_freq: 0.0,
        mid_freq: 0.0,
        high_freq: 0.0,
        sub_bass: 0.0,
        bass: 0.0,
        low_mid: 0.0,
        mid_range: 0.0,
        high_mid: 0.0,
        presence: 0.0,
        brilliance: 0.0
      }
    end

    fft_size = next_power_of_two(min(length(samples), 8192))
    fft_size = max(fft_size, 512)
    hop_size = div(fft_size, 4)
    num_frames = max(1, div(length(samples) - fft_size, hop_size) + 1)
    window = create_hann_window(fft_size)

    accumulated_spectrum = Enum.reduce(0..num_frames-1, [], fn frame, acc ->
      start_pos = frame * hop_size
      frame_samples = Enum.slice(samples, start_pos, fft_size)
      padded = pad_to_length(frame_samples, fft_size)
      windowed = apply_window(padded, window)
      spectrum = compute_spectrum(windowed)

      if acc == [] do
        spectrum
      else
        Enum.zip_with(acc, spectrum, fn a, b -> a + b end)
      end
    end)

    avg_spectrum = Enum.map(accumulated_spectrum, &(&1 / num_frames))
    calibrated_spectrum = calibrate_spectrum(avg_spectrum, fft_size)

    bands = analyze_frequency_bands(calibrated_spectrum, sample_rate, fft_size)

    %{
      full_spectrum: calibrated_spectrum,
      magnitude_db: Enum.map(calibrated_spectrum, &(20 * :math.log10(&1 + 1.0e-10))),
      phase: %{},
      bands: bands,
      features: %{},
      peaks: [],
      fft_size: fft_size,
      sample_rate: sample_rate,
      num_frames: num_frames,
      hop_size: hop_size,
      window_type: :hann,
      calibration_factor: calibrate_spectrum(1.0, fft_size),
      low_freq: Map.get(bands, :low, %{energy: 0.0}).energy,
      mid_freq: Map.get(bands, :mid, %{energy: 0.0}).energy,
      high_freq: Map.get(bands, :high, %{energy: 0.0}).energy,
      sub_bass: Map.get(bands, :sub_bass, %{energy: 0.0}).energy,
      bass: Map.get(bands, :bass, %{energy: 0.0}).energy,
      low_mid: Map.get(bands, :low_mid, %{energy: 0.0}).energy,
      mid_range: Map.get(bands, :mid_range, %{energy: 0.0}).energy,
      high_mid: Map.get(bands, :high_mid, %{energy: 0.0}).energy,
      presence: Map.get(bands, :presence, %{energy: 0.0}).energy,
      brilliance: Map.get(bands, :brilliance, %{energy: 0.0}).energy
    }
  end

  defp extract_samples(audio_data) do
    try do
      data = binary_part(audio_data, 44, byte_size(audio_data) - 44)
      for <<sample::little-16 <- data>>, do: sample / 32768.0
    rescue
      _ -> [0.0]
    end
  end

  defp create_hann_window(size) when size > 1 do
    Enum.map(0..size-1, fn i ->
      0.5 * (1 - :math.cos(2 * :math.pi * i / (size - 1)))
    end)
  end
  defp create_hann_window(_), do: [1.0]

  defp apply_window(samples, window) do
    Enum.zip_with(samples, window, fn s, w -> s * w end)
  end

  defp pad_to_length(list, target) when length(list) >= target, do: list
  defp pad_to_length(list, target) do
    list ++ List.duplicate(0.0, target - length(list))
  end

  defp compute_spectrum(samples) do
    n = length(samples)
    for k <- 0..div(n, 2)-1 do
      {real, imag} = Enum.reduce(0..n-1, {0.0, 0.0}, fn i, {acc_re, acc_im} ->
        angle = 2 * :math.pi * k * i / n
        x = Enum.at(samples, i)
        {acc_re + x * :math.cos(angle), acc_im - x * :math.sin(angle)}
      end)
      :math.sqrt(real*real + imag*imag) / n
    end
  end

  defp calibrate_spectrum(spectrum, fft_size) when is_list(spectrum) do
    coherence_bandwidth = 1.5
    scale_factor = coherence_bandwidth * fft_size / 2
    Enum.map(spectrum, fn x -> x * scale_factor end)
  end
  defp calibrate_spectrum(value, _), do: value

  defp next_power_of_two(n) when n <= 1, do: 1
  defp next_power_of_two(n) do
    round(:math.pow(2, ceil(:math.log2(n))))
  end

  defp suggest_effects_config(analysis, _opts \\ []) do
    config = %{}

    config = if Map.get(analysis, :needs_normalization, true) do
      Map.put(config, :normalize, [preset: :music])
    else
      config
    end

    config = if Map.get(analysis, :frequency_issues, false) do
      Map.put(config, :equalizer, :flat)
    else
      config
    end

    config = if Map.get(analysis, :dynamic_range, 0) > 20 do
      Map.put(config, :compressor, :transparent)
    else
      config
    end

    Map.put(config, :limiter, true)
  end

  defp validate_effects_config(config) do
    %{
      normalize: validate_effect_value(Map.get(config, :normalize)),
      equalizer: validate_effect_value(Map.get(config, :equalizer)),
      compressor: validate_effect_value(Map.get(config, :compressor)),
      reverb: validate_effect_value(Map.get(config, :reverb)),
      limiter: validate_effect_value(Map.get(config, :limiter)),
      order: Map.get(config, :order, @default_pipeline_order),
      cache: Map.get(config, :cache, false),
      processor: Map.get(config, :processor, :auto),
      strict: Map.get(config, :strict, false)
    }
  end

  defp validate_effect_value(nil), do: nil
  defp validate_effect_value(false), do: false
  defp validate_effect_value(true), do: true
  defp validate_effect_value(value), do: value

  defp build_result(audio, cache_hit, start_time, config) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    %{
      audio: audio,
      metadata: %{
        processing_time: duration_ms,
        applied_effects: get_applied_effects(config),
        cache_hit: cache_hit,
        config: config,
        timestamp: DateTime.utc_now()
      }
    }
  end

  defp get_applied_effects(config) do
    @default_pipeline_order
    |> Enum.filter(fn effect ->
      val = Map.get(config, effect)
      val not in [nil, false]
    end)
  end

  defp aggregate_batch_results(results) do
    {successful, failed} = Enum.split_with(results, &match?({:ok, _}, &1))

    if failed == [] do
      processed = Enum.map(successful, fn {:ok, result} -> result end)
      {:ok, processed}
    else
      errors = Enum.map(failed, fn {:error, reason} -> reason end)
      {:error, "Batch failed: #{inspect(errors)}"}
    end
  end

  def calculate_spectral_centroid(spectrum, sample_rate, fft_size) when is_list(spectrum) and length(spectrum) > 0 do
    total = Enum.sum(spectrum)
    if total == 0 do
      0.0
    else
      weighted = spectrum
      |> Enum.with_index()
      |> Enum.map(fn {val, idx} -> val * idx end)
      |> Enum.sum()
      weighted / total * sample_rate / fft_size
    end
  end

  def calculate_spectral_centroid(_, _, _), do: 0.0

  def calculate_spectral_spread(spectrum, centroid, sample_rate, fft_size) when is_list(spectrum) and length(spectrum) > 0 do
    total = Enum.sum(spectrum)
    if total == 0 do
      0.0
    else
      freqs = Enum.with_index(spectrum) |> Enum.map(fn {_, idx} -> idx * sample_rate / fft_size end)
      variance = spectrum
      |> Enum.with_index()
      |> Enum.map(fn {val, idx} -> val * (:math.pow(Enum.at(freqs, idx) - centroid, 2)) end)
      |> Enum.sum()
      :math.sqrt(variance / total)
    end
  end

  def calculate_spectral_spread(_, _, _, _), do: 0.0

  def calculate_spectral_rolloff(spectrum, sample_rate, fft_size, threshold) when is_list(spectrum) and length(spectrum) > 0 do
    total = Enum.sum(spectrum)
    if total == 0 do
      0.0
    else
      target = total * threshold
      {rolloff, _} = spectrum
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0.0}, fn {val, idx}, {_, acc} ->
        new_acc = acc + val
        if new_acc >= target and acc < target do
          {idx * sample_rate / fft_size, new_acc}
        else
          {idx * sample_rate / fft_size, new_acc}
        end
      end)
      rolloff
    end
  end

  def calculate_spectral_rolloff(_, _, _, _), do: 0.0

  def calculate_spectral_flatness(spectrum) when is_list(spectrum) and length(spectrum) > 0 do
    n = length(spectrum)
    geometric = :math.pow(Enum.product(spectrum), 1.0 / n)
    arithmetic = Enum.sum(spectrum) / n
    if arithmetic == 0, do: 0.0, else: geometric / arithmetic
  end

  def calculate_spectral_flatness(_), do: 0.0

  def calculate_spectral_crest(spectrum) when is_list(spectrum) and length(spectrum) > 0 do
    peak = Enum.max(spectrum)
    rms = :math.sqrt(Enum.sum(Enum.map(spectrum, &(&1 * &1))) / length(spectrum))
    if rms == 0, do: 0.0, else: peak / rms
  end

  def calculate_spectral_crest(_), do: 0.0

  def calculate_spectral_slope(spectrum, sample_rate, fft_size) when is_list(spectrum) and length(spectrum) > 1 do
    n = length(spectrum)
    x_mean = (n - 1) / 2
    y_mean = Enum.sum(spectrum) / n

    num = spectrum
    |> Enum.with_index()
    |> Enum.map(fn {val, idx} -> (idx - x_mean) * (val - y_mean) end)
    |> Enum.sum()

    den = spectrum
    |> Enum.with_index()
    |> Enum.map(fn {_, idx} -> (idx - x_mean) * (idx - x_mean) end)
    |> Enum.sum()

    if den == 0, do: 0.0, else: num / den * sample_rate / fft_size
  end

  def calculate_spectral_slope(_, _, _), do: 0.0

  def analyze_frequency_bands(spectrum, sample_rate, fft_size) when is_list(spectrum) and length(spectrum) > 0 do
    bands = %{
      sub_bass: {20, 60},
      bass: {60, 250},
      low_mid: {250, 500},
      mid: {500, 2000},
      high_mid: {2000, 4000},
      presence: {4000, 6000},
      brilliance: {6000, 20000}
    }

    nyquist = sample_rate / 2
    bin_width = sample_rate / fft_size

    Map.new(bands, fn {name, {low, high}} ->
      low_bin = max(0, round(low / bin_width))
      high_bin = min(length(spectrum) - 1, round(high / bin_width))

      band_energy = spectrum
      |> Enum.slice(low_bin, high_bin - low_bin + 1)
      |> Enum.sum()

      {name, band_energy}
    end)
  end

  def analyze_frequency_bands(_, _, _), do: %{}

  def detect_spectral_issues(spectrum, bands) when is_list(spectrum) do
    issues = []

    issues = if length(spectrum) > 0 do
      total = Enum.sum(spectrum)
      low_energy = Map.get(bands, :sub_bass, 0) + Map.get(bands, :bass, 0)
      if total > 0 and low_energy / total < 0.05 do
        ["low_bass" | issues]
      else
        issues
      end
    else
      issues
    end

    issues = if length(spectrum) > 10 do
      high_bins = Enum.slice(spectrum, -10, 10)
      if Enum.sum(high_bins) / Enum.sum(spectrum) < 0.01 do
        ["low_high_freq" | issues]
      else
        issues
      end
    else
      issues
    end

    Enum.reverse(issues)
  end

  def detect_spectral_issues(_, _), do: []

  def detect_spectral_peaks(spectrum, sample_rate, fft_size) when is_list(spectrum) and length(spectrum) > 2 do
    bin_width = sample_rate / fft_size

    spectrum
    |> Enum.with_index()
    |> Enum.drop(1)
    |> Enum.drop(-1)
    |> Enum.filter(fn {{_, idx}, val} ->
      prev = Enum.at(spectrum, idx - 1)
      next_val = Enum.at(spectrum, idx + 1)
      val > prev and val > next_val
    end)
    |> Enum.take(10)
    |> Enum.map(fn {{val, idx}, _} ->
      %{frequency: idx * bin_width, magnitude: val}
    end)
  end

  def detect_spectral_peaks(_, _, _), do: []

  # ========== PHASE ANALYSIS FUNCTIONS ==========

  def compute_phase(audio_data, fft_size, sample_rate) when is_map(audio_data) do
    samples = Map.get(audio_data, :samples, [])
    if is_list(samples) and length(samples) > 0 do
      samples
      |> Enum.take(fft_size)
      |> Enum.with_index()
      |> Enum.map(fn {val, idx} ->
        # Симулируем фазу: арктангенс мнимой части к реальной
        real = val
        imag = :math.sin(2 * :math.pi() * idx / fft_size)
        :math.atan2(imag, real)
      end)
    else
      []
    end
  end

  def compute_phase(_, _, _), do: []

  def analyze_phase_coherence(phase_data, _sample_rate) when is_list(phase_data) and length(phase_data) > 1 do
    diffs = phase_data
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> :math.cos(b - a) end)

    Enum.sum(diffs) / length(diffs)
  end

  def analyze_phase_coherence(_, _), do: 0.0

  def analyze_stereo_phase(phase_data) when is_list(phase_data) and length(phase_data) > 0 do
    # Разделяем на левый и правый канал (чётные/нечётные)
    left = phase_data |> Enum.take_every(2)
    right = phase_data |> Enum.drop(1) |> Enum.take_every(2)

    if length(left) > 0 and length(right) > 0 do
      left_avg = Enum.sum(left) / length(left)
      right_avg = Enum.sum(right) / length(right)
      right_avg - left_avg
    else
      0.0
    end
  end

  def analyze_stereo_phase(_), do: 0.0

  def compute_group_delay(phase_data, sample_rate) when is_list(phase_data) and length(phase_data) > 1 do
    unwrapped = unwrap_phase(phase_data)
    diffs = unwrapped
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> -(b - a) end)

    Enum.sum(diffs) / length(diffs) / (2 * :math.pi()) * sample_rate
  end

  def compute_group_delay(_, _), do: 0.0

  def compute_instantaneous_frequency(phase_data, sample_rate) when is_list(phase_data) and length(phase_data) > 1 do
    unwrapped = unwrap_phase(phase_data)
    diffs = unwrapped
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> (b - a) / (2 * :math.pi()) * sample_rate end)

    diffs
  end

  def compute_instantaneous_frequency(_, _), do: []

  def detect_phase_anomalies(phase_data) when is_list(phase_data) and length(phase_data) > 2 do
    unwrapped = unwrap_phase(phase_data)
    diffs = unwrapped
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> abs(b - a) end)

    mean = Enum.sum(diffs) / length(diffs)
    threshold = mean * 3

    diffs
    |> Enum.with_index()
    |> Enum.filter(fn {diff, _} -> diff > threshold end)
    |> Enum.map(fn {diff, idx} -> %{index: idx, jump: diff} end)
  end

  def detect_phase_anomalies(_), do: []

  def detect_phase_cancellation(phase_data) when is_list(phase_data) and length(phase_data) > 1 do
    coherence = analyze_phase_coherence(phase_data, 44100)
    coherence < 0.5
  end

  def detect_phase_cancellation(_), do: false

  def unwrap_phase(phase_data) when is_list(phase_data) and length(phase_data) > 0 do
    {_, result} = phase_data
    |> Enum.reduce({0.0, []}, fn phase, {last, acc} ->
      diff = phase - last
      corrected = if diff > :math.pi(), do: phase - 2 * :math.pi(), else: phase
      corrected = if diff < -:math.pi(), do: phase + 2 * :math.pi(), else: corrected
      {corrected, acc ++ [corrected]}
    end)
    result
  end

  def unwrap_phase(_), do: []
end
