defmodule MusicCore.AudioEffects.Effects.EffectsManager do
  @moduledoc """
  Менеджер эффектов - центральный координатор применения аудио эффектов.

  Функционал:
  - Управление пользовательскими настройками эффектов
  - Применение цепочек эффектов с оптимальным порядком
  - Кэширование результатов обработки
  - Мониторинг производительности
  - Интеграция с внешними сервисами (Go, Java)
  - Graceful degradation при недоступности компонентов
  """
  @behaviour MusicCore.AudioEffects.Effect
  use GenServer
  require Logger

  alias MusicCore.AudioEffects.Effects.{
    Normalizer,
    Equalizer,
    Compressor,
    Reverb,
    Chorus,
    Analyzer,
    CacheManager,
    Native.DSP
  }

  alias MusicCore.Services.{GoProcessor, JavaGateway}

  # API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    case Redix.child_spec(name: :redix) do
      %{start: {_, :start_link, _}} ->
        {:ok, %{redis: :redix}}
      _ ->
        {:ok, %{redis: nil}}
    end
  end

  defp get_current_load do
    run_queue = :erlang.statistics(:run_queue)
    schedulers = :erlang.system_info(:schedulers_online)
    min(1.0, run_queue / schedulers)
  end

  @doc """
  Основной метод применения эффектов к аудио.
  """
  def apply_effects(audio_data, user_id, context \\ []) do
    GenServer.call(__MODULE__, {:apply_effects, audio_data, user_id, context})
  end

  @doc """
  Обновление настроек эффектов для пользователя.
  """
  def update_user_settings(user_id, settings) do
    GenServer.cast(__MODULE__, {:update_settings, user_id, settings})
  end

  @doc """
  Получение настроек пользователя.
  """
  def get_user_settings(user_id) do
    GenServer.call(__MODULE__, {:get_settings, user_id})
  end

  defp validate_effect_value(nil), do: nil
  defp validate_effect_value(false), do: false
  defp validate_effect_value(true), do: true
  defp validate_effect_value(value), do: value

  @doc """
  Применение пресета эффектов.
  """
  def apply_preset(audio_data, preset_name, context \\ []) do
    GenServer.call(__MODULE__, {:apply_preset, audio_data, preset_name, context})
  end

  @doc """
  Создание кастомного пресета.
  """
  def create_preset(name, config, user_id \\ nil) do
    GenServer.call(__MODULE__, {:create_preset, name, config, user_id})
  end

  @doc """
  Анализ аудио и подбор оптимальных эффектов.
  """
  def analyze_and_apply(audio_data, user_id, context \\ []) do
    GenServer.call(__MODULE__, {:analyze_and_apply, audio_data, user_id, context})
  end

  @doc """
  Пакетная обработка нескольких аудио фрагментов.
  """
  def apply_batch(audio_list, user_id, context \\ []) do
    GenServer.call(__MODULE__, {:apply_batch, audio_list, user_id, context})
  end

  @doc """
  Получение статистики обработки.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Graceful shutdown с сохранением состояния.
  """
  def graceful_shutdown do
    GenServer.call(__MODULE__, :graceful_shutdown)
  end

  # Сервер
  def init(opts) do
    user_settings = load_user_settings_from_redis()
    presets = load_presets()
    cache_ref = CacheManager.init_cache()
    schedule_stats_collection()

    Logger.info("EffectsManager started with #{map_size(user_settings)} user settings")

    {:ok, %{
      user_settings: user_settings,
      active_effects: %{},
      presets: presets,
      cache: cache_ref,
      stats: %{
        total_processed: 0,
        cache_hits: 0,
        cache_misses: 0,
        processing_time_sum: 0,
        last_processed: nil,
        errors: 0
      },
      performance_monitor: init_performance_monitor(),
      opts: opts
    }}
  end

  def handle_call({:apply_effects, audio_data, user_id, context}, state) do
    start_time = System.monotonic_time()
    cache_key = generate_cache_key(audio_data, user_id, context)
    case CacheManager.get(state.cache, cache_key) do
      {:ok, cached_result} ->
        new_state = update_stats(state, :cache_hit, start_time)
        Logger.debug("Cache hit for user #{user_id}")
        {:reply, cached_result, new_state}

      :not_found ->
        process_audio(audio_data, user_id, context, state, start_time, cache_key)
    end
  end

  def handle_call({:get_settings, user_id}, state) do
    settings = Map.get(state.user_settings, user_id, %{})
    {:reply, {:ok, settings}, state}
  end

  def handle_call({:apply_preset, audio_data, preset_name, context}, state) do
    start_time = System.monotonic_time()
    preset_config = Map.get(state.presets, preset_name, state.presets.default)
    result = apply_effects_chain(audio_data, preset_config, context)
    new_state = update_stats(state, :preset_processed, start_time)
    {:reply, result, new_state}
  end

  def handle_call({:create_preset, name, config, user_id}, state) do
    validated_config = validate_preset_config(config)
    new_presets = Map.put(state.presets, name, validated_config)
    Logger.info("Created preset '#{name}' for user #{user_id || "system"}")
    {:reply, {:ok, name}, %{state | presets: new_presets}}
  end

  def handle_call({:analyze_and_apply, audio_data, user_id, context}, state) do
    start_time = System.monotonic_time()
    case Normalizer.analyze_audio(audio_data) do
      {:ok, analysis} ->
        suggested_config = suggest_effects_based_on_analysis(analysis, user_id, state)
        result = apply_effects_chain(audio_data, suggested_config, context)
        new_state = update_stats(state, :analyzed_and_processed, start_time)
        {:reply, result, new_state}
      {:error, reason} ->
        Logger.error("Audio analysis failed: #{reason}")
        {:reply, {:error, :analysis_failed}, state}
    end
  end

  def handle_call({:apply_batch, audio_list, user_id, context}, state) do
    max_concurrent = Application.get_env(:music_core, :audio_processing)[:max_concurrent_streams] || 5
    results = audio_list
    |> Enum.chunk_every(max_concurrent)
    |> Enum.flat_map(fn chunk ->
      chunk |> Enum.map(fn audio ->
        Task.async(fn ->
          apply_effects(audio, user_id, context)
        end)
      end) |> Task.await_many(30000)
    end)
    {:reply, results, state}
  end

  def handle_call(:get_stats, state) do
    avg_time = if state.stats.total_processed > 0 do
      state.stats.processing_time_sum / state.stats.total_processed
    else
      0
    end
    stats = %{
      state.stats |
      avg_processing_time: avg_time,
      cache_hit_rate: calculate_hit_rate(state.stats),
      uptime: System.monotonic_time() - state.performance_monitor.start_time
    }
    {:reply, stats, state}
  end

  def handle_call(:graceful_shutdown, state) do
    Logger.info("EffectsManager: Starting graceful shutdown")
    save_user_settings_to_redis(state.user_settings)
    save_presets(state.presets)
    save_stats(state.stats)
    CacheManager.cleanup(state.cache)

    Logger.info("EffectsManager: Graceful shutdown completed")
    {:stop, :normal, :ok, state}
  end

  def handle_cast({:update_settings, user_id, settings}, state) do
    validated_settings = validate_user_settings(settings)
    new_settings = Map.put(state.user_settings, user_id, validated_settings)
    Task.start(fn ->
      save_user_settings_to_redis(%{user_id => validated_settings})
    end)
    {:noreply, %{state | user_settings: new_settings}}
  end

  def handle_info(:collect_stats, state) do
    current_stats = state.stats
    Logger.info("""
    EffectsManager Stats:
    - Total processed: #{current_stats.total_processed}
    - Cache hits: #{current_stats.cache_hits}
    - Cache miss: #{current_stats.cache_misses}
    - Avg time: #{current_stats.processing_time_sum / max(current_stats.total_processed, 1)}ms
    - Errors: #{current_stats.errors}
    """)
    save_stats(current_stats)
    schedule_stats_collection()
    {:noreply, state}
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp process_audio(audio_data, user_id, context, state, start_time, cache_key) do
    try do
      user_settings = Map.get(state.user_settings, user_id, %{})
      full_config = merge_settings_with_context(user_settings, context)
      result = apply_effects_chain(audio_data, full_config, context)
      CacheManager.put(state.cache, cache_key, result, ttl: get_cache_ttl(context))
      new_state = update_stats(state, :processed, start_time)
      {:reply, result, new_state}
    rescue
      error ->
        Logger.error("Audio processing failed: #{inspect(error)}")
        fallback_result = {:ok, audio_data, %{fallback: true, error: inspect(error)}}
        new_state = update_stats(state, :error, start_time)
        {:reply, fallback_result, new_state}
    end
  end

  defp apply_effects_chain(audio_data, config, context) do
    order = config[:order] || [:normalize, :equalizer, :compressor, :chorus, :reverb, :limiter]
    processor = select_processor(audio_data, config, context)
    result = Enum.reduce(order, {:ok, audio_data, %{}}, fn
      effect, {:ok, current_audio, meta} ->
        apply_single_effect(effect, current_audio, config, meta, processor, context)
      _, error ->
        error
    end)
    case result do
      {:ok, processed_audio, metadata} ->
        metadata = Map.merge(metadata, %{
          processor: processor,
          effects_applied: order,
          timestamp: DateTime.utc_now()
        })
        {:ok, processed_audio, metadata}
      error ->
        error
    end
  end

  defp apply_single_effect(:normalize, audio, config, meta, processor, context) do
    case config[:normalize] do
      nil -> {:ok, audio, meta}
      false -> {:ok, audio, meta}
      true ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :strategy, :streaming), else: opts
        Normalizer.normalize(audio, :streaming, opts)
      params ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :strategy, :streaming), else: opts
        Normalizer.normalize(audio, params, opts)
    end
  end

  defp apply_single_effect(:equalizer, audio, config, meta, processor, context) do
    case config[:equalizer] do
      nil -> {:ok, audio, meta}
      bands when is_map(bands) ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :quality, :fast), else: Keyword.put(opts, :quality, :high)
        Equalizer.apply_equalizer(audio, bands, opts)
      preset when is_atom(preset) ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :quality, :fast), else: Keyword.put(opts, :quality, :high)
        Equalizer.apply_equalizer(audio, preset, opts)
    end
  end

  defp apply_single_effect(:compressor, audio, config, meta, processor, context) do
    case config[:compressor] do
      nil -> {:ok, audio, meta}
      params when is_map(params) ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :lookahead, false), else: opts
        Compressor.compress(audio, params, opts)
      preset when is_atom(preset) ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :lookahead, false), else: opts
        Compressor.compress(audio, preset, opts)
    end
  end

  defp apply_single_effect(:chorus, audio, config, meta, processor, context) do
    case config[:chorus] do
      nil -> {:ok, audio, meta}
      false -> {:ok, audio, meta}
      true ->
        opts = [processor: processor]
        Chorus.add_chorus(audio, :classic, opts)
      params when is_map(params) ->
        opts = [processor: processor]
        Chorus.add_chorus(audio, params, opts)
      preset when is_atom(preset) ->
        opts = [processor: processor]
        Chorus.add_chorus(audio, preset, opts)
    end
  end

  defp apply_single_effect(:reverb, audio, config, meta, processor, context) do
    case config[:reverb] do
      nil -> {:ok, audio, meta}
      params when is_map(params) ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :ir_length, :short), else: Keyword.put(opts, :ir_length, :full)
        Reverb.add(audio, params, opts)
      preset when is_atom(preset) ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :ir_length, :short), else: Keyword.put(opts, :ir_length, :full)
        Reverb.add(audio, preset, opts)
    end
  end

  defp apply_single_effect(:limiter, audio, config, meta, processor, context) do
    case config[:limiter] do
      nil -> {:ok, audio, meta}
      false -> {:ok, audio, meta}
      true ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :attack, :fast), else: opts
        Compressor.limit(audio, -1.5, opts)
      params when is_map(params) ->
        opts = [processor: processor]
        opts = if context[:realtime], do: Keyword.put(opts, :attack, :fast), else: opts
        Compressor.limit(audio, params.threshold || -1.5, opts)
    end
  end

  defp select_processor(audio_data, config, context) do
    audio_size = byte_size(audio_data)
    realtime? = context[:realtime] == true
    force_processor = config[:force_processor]

    cond do
      force_processor -> force_processor
      realtime? and Code.ensure_loaded?(DSP) -> :native
      audio_size > 10_000_000 -> :go
      Code.ensure_loaded?(DSP) -> :native
      true -> :ffmpeg
    end
  end

  defp generate_cache_key(audio_data, user_id, context) do
    audio_hash = :crypto.hash(:sha256, audio_data) |> Base.encode64()
    config_hash = :crypto.hash(:sha256, "#{user_id}#{inspect(context)}") |> Base.encode64()
    "effects:#{user_id}:#{audio_hash}:#{config_hash}"
  end

  defp get_cache_ttl(context) do
    case context[:cache_ttl] do
      ttl when is_integer(ttl) -> ttl
      _ -> 3600
    end
  end

  defp merge_settings_with_context(user_settings, context) do
    Map.merge(user_settings, %{
      normalize: context[:auto_normalize] != false,
      limiter: context[:prevent_clipping] != false
    })
  end

  defp validate_user_settings(settings) do
    %{
      equalizer: validate_equalizer_settings(settings[:equalizer]),
      compressor: validate_compressor_settings(settings[:compressor]),
      chorus: validate_chorus_settings(settings[:chorus]),
      reverb: validate_reverb_settings(settings[:reverb]),
      normalize: settings[:normalize] == true,
      limiter: settings[:limiter] == true
    }
  end

  defp validate_equalizer_settings(nil), do: nil
  defp validate_equalizer_settings(bands) when is_map(bands) do
    Enum.into(bands, %{}, fn {freq, gain} ->
      {to_string(freq), clamp(gain, -12.0, 12.0)}
    end)
  end

  defp validate_compressor_settings(nil), do: nil
  defp validate_compressor_settings(params) when is_map(params) do
    %{
      threshold: clamp(params.threshold || -20.0, -60.0, 0.0),
      ratio: max(params.ratio || 4.0, 1.0),
      attack: max(params.attack || 20, 0),
      release: max(params.release || 250, 0)
    }
  end

  defp validate_chorus_settings(nil), do: nil
  defp validate_chorus_settings(true), do: true
  defp validate_chorus_settings(preset) when is_atom(preset) do
    preset
  end
  defp validate_chorus_settings(params) when is_map(params) do
    %{
      mix: clamp(Map.get(params, :mix, 0.5), 0.0, 1.0),
      voices: Map.get(params, :voices, 4),
      rate: Map.get(params, :rate, 0.8),
      depth: Map.get(params, :depth, 6.0),
      feedback: clamp(Map.get(params, :feedback, 0.1), 0.0, 1.0),
      stereo_width: clamp(Map.get(params, :stereo_width, 0.8), 0.0, 1.0)
    }
  end
  defp validate_chorus_settings(_), do: nil

  defp validate_reverb_settings(nil), do: nil
  defp validate_reverb_settings(params) when is_map(params) do
    %{
      room_size: clamp(params.room_size || 0.5, 0.0, 1.0),
      damping: clamp(params.damping || 0.5, 0.0, 1.0),
      wet_level: clamp(params.wet_level || 0.3, 0.0, 1.0),
      dry_level: clamp(params.dry_level || 0.7, 0.0, 1.0)
    }
  end

  defp validate_preset_config(config) do
    %{
      normalize: config[:normalize] == true,
      equalizer: validate_equalizer_settings(config[:equalizer]),
      compressor: validate_compressor_settings(config[:compressor]),
      chorus: validate_chorus_settings(config[:chorus]),
      reverb: validate_reverb_settings(config[:reverb]),
      limiter: config[:limiter] == true,
      order: config[:order] || [:normalize, :equalizer, :compressor, :chorus, :reverb, :limiter]
    }
  end

  defp suggest_effects_based_on_analysis(analysis, user_id, state) do
    base_config = Map.get(state.user_settings, user_id, %{})
    config = if analysis.needs_normalization do
      Map.put(base_config, :normalize, true)
    else
      base_config
    end
    config = if analysis.frequency_imbalance do
      eq_bands = suggest_equalizer_bands(analysis)
      Map.put(config, :equalizer, eq_bands)
    else
      config
    end
    config = if analysis.dynamic_range > 20 do
      compressor_params = suggest_compressor_params(analysis)
      Map.put(config, :compressor, compressor_params)
    else
      config
    end
    config = if Map.get(analysis, :stereo_width, 1.0) < 0.5 do
      chorus_config = %{
        mix: 0.3,
        voices: 4,
        rate: 0.6,
        depth: 4.0,
        stereo_width: 1.0
      }
      Map.put(config, :chorus, chorus_config)
    else
      config
    end
    Map.put(config, :limiter, true)
  end

  defp suggest_equalizer_bands(analysis) do
    %{
      "20" => calculate_band_gain(analysis, 20, 60,
        target: -12.0, max_boost: 6.0, max_cut: -6.0,
        description: "sub_bass"
      ),
      "60" => calculate_band_gain(analysis, 60, 100,
        target: -18.0, max_boost: 4.0, max_cut: -8.0,
        description: "bass_fundamental"
      ),
      "100" => calculate_band_gain(analysis, 100, 160,
        target: -20.0, max_boost: 3.0, max_cut: -6.0,
        description: "bass_harmonics"
      ),
      "160" => calculate_band_gain(analysis, 160, 250,
        target: -22.0, max_boost: 2.0, max_cut: -4.0,
        description: "low_mids"
      ),
      "250" => calculate_band_gain(analysis, 250, 400,
        target: -24.0, max_boost: 3.0, max_cut: -6.0,
        description: "low_mids_mud"
      ),
      "400" => calculate_band_gain(analysis, 400, 630,
        target: -24.0, max_boost: 3.0, max_cut: -4.0,
        description: "low_mids_boxy"
      ),
      "630" => calculate_band_gain(analysis, 630, 1000,
        target: -24.0, max_boost: 3.0, max_cut: -4.0,
        description: "low_mids_honky"
      ),
      "1000" => calculate_band_gain(analysis, 1000, 1600,
        target: -22.0, max_boost: 4.0, max_cut: -5.0,
        description: "mid_presence"
      ),
      "1600" => calculate_band_gain(analysis, 1600, 2500,
        target: -22.0, max_boost: 4.0, max_cut: -5.0,
        description: "mid_nasality"
      ),
      "2500" => calculate_band_gain(analysis, 2500, 4000,
        target: -24.0, max_boost: 3.0, max_cut: -6.0,
        description: "mid_harshness"
      ),
      "4000" => calculate_band_gain(analysis, 4000, 5000,
        target: -28.0, max_boost: 4.0, max_cut: -8.0,
        description: "high_mids_presence"
      ),
      "5000" => calculate_band_gain(analysis, 5000, 6300,
        target: -30.0, max_boost: 3.0, max_cut: -8.0,
        description: "high_mids_sibilance"
      ),
      "6300" => calculate_band_gain(analysis, 6300, 8000,
        target: -32.0, max_boost: 2.0, max_cut: -6.0,
        description: "high_mids_air"
      ),
      "8000" => calculate_band_gain(analysis, 8000, 10000,
        target: -35.0, max_boost: 4.0, max_cut: -4.0,
        description: "high_air"
      ),
      "10000" => calculate_band_gain(analysis, 10000, 12500,
        target: -40.0, max_boost: 4.0, max_cut: -4.0,
        description: "high_brilliance"
      ),
      "12500" => calculate_band_gain(analysis, 12500, 16000,
        target: -45.0, max_boost: 3.0, max_cut: -3.0,
        description: "high_sparkle"
      ),
      "16000" => calculate_band_gain(analysis, 16000, 20000,
        target: -50.0, max_boost: 2.0, max_cut: -2.0,
        description: "high_ultra"
      )
    }
  end

  defp calculate_band_gain(analysis, low_freq, high_freq, opts) do
    target = Keyword.get(opts, :target, -20.0)
    max_boost = Keyword.get(opts, :max_boost, 6.0)
    max_cut = Keyword.get(opts, :max_cut, -6.0)
    band_energy = get_band_energy(analysis, low_freq, high_freq)
    delta = target - band_energy
    adjusted_delta = adjust_for_neighbors(analysis, delta, low_freq, high_freq)
    clamp(adjusted_delta, max_cut, max_boost)
  end

  defp get_band_energy(analysis, low_freq, high_freq) do
    case analysis.spectrum do
      %{bands: bands} ->
        relevant_bands = Enum.filter(bands, fn {freq, _} ->
          freq >= low_freq and freq <= high_freq
        end)

        if relevant_bands == [] do
          analysis.low_energy
        else
          {sum, count} = Enum.reduce(relevant_bands, {0, 0}, fn {freq, energy}, {s, c} ->
            {s + energy * weight(freq, low_freq, high_freq), c + 1}
          end)
          sum / count
        end

      _ ->
        cond do
          high_freq <= 60 -> analysis.sub_bass || analysis.low_energy
          high_freq <= 250 -> analysis.bass || analysis.low_energy
          high_freq <= 4000 -> analysis.mid_energy
          high_freq <= 20000 -> analysis.high_energy
          true -> -50.0
        end
    end
  end

  defp weight(freq, low, high) do
    center = (low + high) / 2
    spread = (high - low) / 2
    1.0 - min(1.0, abs(freq - center) / spread)
  end

  defp adjust_for_neighbors(analysis, delta, low_freq, high_freq) do
    lower_band = get_band_energy(analysis, low_freq - (high_freq - low_freq), low_freq)
    higher_band = get_band_energy(analysis, high_freq, high_freq + (high_freq - low_freq))
    avg_neighbor = (lower_band + higher_band) / 2
    if abs(avg_neighbor - analysis.current_level) > 10 do
      delta * 0.7
    else
      delta
    end
  end

  defp clamp(value, min, max) when value < min, do: min
  defp clamp(value, min, max) when value > max, do: max
  defp clamp(value, _, _), do: value

  defp suggest_compressor_params(analysis) do
    %{
      threshold: max(analysis.peak_level - 10, -30),
      ratio: if(analysis.crest_factor > 15, do: 6.0, else: 3.0),
      attack: if(analysis.transient_energy > 0.5, do: 30, else: 20),
      release: 250
    }
  end

  defp load_user_settings_from_redis do
    try do
      case Redix.command(:redix, ["KEYS", "user:settings:*"]) do
        {:ok, keys} ->
          keys
          |> Enum.map(fn key ->
            case Redix.command(:redix, ["GET", key]) do
              {:ok, settings_json} ->
                user_id = String.replace(key, "user:settings:", "")
                {user_id, Jason.decode!(settings_json, keys: :atoms)}
              _ -> nil
            end
          end)
          |> Enum.filter(& &1)
          |> Enum.into(%{})

        _ -> %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp save_user_settings_to_redis(settings) do
    Task.start(fn ->
      Enum.each(settings, fn {user_id, user_settings} ->
        key = "user:settings:#{user_id}"
        json = Jason.encode!(user_settings)
        Redix.command(:redix, ["SET", key, json, "EX", 86400])
      end)
    end)
  end

  defp load_presets do
    default_presets = %{
      default: %{normalize: true, limiter: true},
      bass_boost: %{equalizer: %{"60" => 6.0, "230" => 3.0, "910" => -3.0}},
      vocal_boost: %{equalizer: %{"1000" => 3.0, "3000" => 2.0, "5000" => 1.0}},
      radio: %{
        normalize: [target_lufs: -10],
        equalizer: %{"100" => 2.0, "1000" => 1.0, "5000" => 3.0},
        compressor: %{threshold: -12, ratio: 6},
        limiter: %{threshold: -1.0}
      }
    }

    try do
      custom_presets = :ets.tab2list(:audio_effects_presets)
        |> Enum.into(%{})
      Map.merge(default_presets, custom_presets)
    rescue
      _ -> default_presets
    end
  end

  defp save_presets(presets) do
    :ets.delete(:audio_effects_presets)
    :ets.new(:audio_effects_presets, [:named_table, :public])

    Enum.each(presets, fn {name, config} ->
      :ets.insert(:audio_effects_presets, {name, config})
    end)
  end

  defp save_stats(stats) do
    Task.start(fn ->
      json = Jason.encode!(%{
        timestamp: DateTime.utc_now(),
        stats: stats
      })
      Redix.command(:redix, ["SET", "stats:effects_manager", json, "EX", 300])
    end)
  end

  defp update_stats(state, type, start_time) do
    duration = System.monotonic_time() - start_time
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    new_stats = case type do
      :cache_hit ->
        %{state.stats | cache_hits: state.stats.cache_hits + 1}

      :processed ->
        %{
          state.stats |
          total_processed: state.stats.total_processed + 1,
          cache_misses: state.stats.cache_misses + 1,
          processing_time_sum: state.stats.processing_time_sum + duration_ms,
          last_processed: DateTime.utc_now()
        }

      :preset_processed ->
        %{
          state.stats |
          total_processed: state.stats.total_processed + 1,
          processing_time_sum: state.stats.processing_time_sum + duration_ms
        }

      :analyzed_and_processed ->
        %{
          state.stats |
          total_processed: state.stats.total_processed + 1,
          processing_time_sum: state.stats.processing_time_sum + duration_ms
        }

      :error ->
        %{state.stats | errors: state.stats.errors + 1}
    end

    %{state | stats: new_stats}
  end

  defp calculate_hit_rate(stats) do
    total = stats.cache_hits + stats.cache_misses
    if total > 0 do
      stats.cache_hits / total
    else
      0.0
    end
  end

  defp init_performance_monitor do
    %{
      start_time: System.monotonic_time(),
      last_check: DateTime.utc_now(),
      memory_samples: []
    }
  end

  defp schedule_stats_collection do
    Process.send_after(self(), :collect_stats, 60000)
  end

  def find_spectral_peaks(analysis) do
    spectrum = case analysis do
      %{spectrum: spec} -> spec
      spec when is_list(spec) -> spec
      _ -> []
    end

    spectrum
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.filter(fn [_, {_, mag2}, _] -> mag2 > 0.1 end)
    |> Enum.map(fn [{f1, m1}, {f2, m2}, {f3, m3}] ->
      if m2 > m1 and m2 > m3 do
        {f2, m2}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_, mag} -> mag end, :desc)
    |> Enum.take(10)
  end

  defp suggest_eq_bands_with_q(analysis) do
    peaks = find_spectral_peaks(analysis)

    Enum.map(peaks, fn {freq, mag} ->
      q_factor = calculate_q_factor(analysis, freq)
      %{
        frequency: freq,
        gain: -mag,
        q: q_factor,
        filter_type: :peak
      }
    end)
  end

  def calculate_q_factor(analysis, center_freq) do
    peak_width = analyze_peak_width(analysis, center_freq)
    if peak_width > 0 do
      center_freq / peak_width
    else
      1.0
    end
  end

  defp analyze_peak_width(analysis, center_freq) do
    peak_mag = get_peak_magnitude(analysis, center_freq)
    threshold = peak_mag * 0.707

    sorted = Enum.sort_by(analysis, &elem(&1, 0))

    left = Enum.find(Enum.reverse(sorted), fn {f, mag} -> f <= center_freq and mag <= threshold end)
    right = Enum.find(sorted, fn {f, mag} -> f >= center_freq and mag <= threshold end)

    if left && right do
      elem(right, 0) - elem(left, 0)
    else
      50
    end
  end

  defp get_peak_magnitude(analysis, center_freq) do
    case Enum.find(analysis, fn {f, _} -> abs(f - center_freq) < 10 end) do
      {_, mag} -> mag
      nil ->
        sorted = Enum.sort_by(analysis, &elem(&1, 0))
        case find_closest(sorted, center_freq) do
          {_, mag} -> mag
          nil -> 1.0
        end
    end
  end

  defp find_closest(sorted, target) do
    Enum.reduce(sorted, nil, fn {f, mag}, closest ->
      if closest == nil or abs(f - target) < abs(elem(closest, 0) - target) do
        {f, mag}
      else
        closest
      end
    end)
  end
end
