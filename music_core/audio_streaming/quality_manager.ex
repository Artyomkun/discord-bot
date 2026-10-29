defmodule MusicCore.AudioStreaming.QualityManager do
  @moduledoc """
  Управление качеством обслуживания (QoS) для аудио-потоков.
  Определяет профили качества и применяет ограничения для разных типов задач.
  """

  @quality_profiles %{
    # Для премиум пользователей
    premium: %{
      max_bitrate: 320_000,
      sample_rate: 48_000,
      stereo: true,
      max_latency_ms: 100,
      priority: :high,
      max_retries: 5,
      retry_backoff: :exponential,
      effects: [:reverb, :eq, :compressor, :chorus]
    },

    # Сбалансированный профиль (по умолчанию)
    balanced: %{
      max_bitrate: 192_000,
      sample_rate: 44_100,
      stereo: true,
      max_latency_ms: 200,
      priority: :normal,
      max_retries: 3,
      retry_backoff: :linear,
      effects: [:eq, :compressor]
    },

    # Экономичный (для слабых каналов)
    economical: %{
      max_bitrate: 96_000,
      sample_rate: 22_050,
      stereo: false,
      max_latency_ms: 500,
      priority: :low,
      max_retries: 2,
      retry_backoff: :fixed,
      effects: [:compressor]
    },

    # Для live-трансляций (минимальная задержка)
    live: %{
      max_bitrate: 128_000,
      sample_rate: 44_100,
      stereo: true,
      max_latency_ms: 50,
      priority: :high,
      max_retries: 1,
      retry_backoff: :none,
      effects: []
    },

    # Для скачивания (максимальное качество)
    download: %{
      max_bitrate: 1_411_200,
      sample_rate: 44_100,
      stereo: true,
      max_latency_ms: 5_000,
      priority: :low,
      max_retries: 10,
      retry_backoff: :exponential,
      effects: [:reverb, :eq, :compressor, :chorus, :delay, :distortion]
    }
  }

  @doc """
  Получить настройки QoS для заданного профиля и приоритета.
  """
  def get_qos_settings(profile \\ :balanced, priority \\ nil) do
    profile_settings = Map.get(@quality_profiles, profile, @quality_profiles.balanced)

    # Если приоритет передан, он имеет больший вес
    effective_priority = priority || profile_settings.priority

    %{
      profile: profile,
      priority: effective_priority,
      max_bitrate: profile_settings.max_bitrate,
      sample_rate: profile_settings.sample_rate,
      stereo: profile_settings.stereo,
      max_latency_ms: profile_settings.max_latency_ms,
      max_retries: profile_settings.max_retries,
      retry_backoff: profile_settings.retry_backoff,
      allowed_effects: profile_settings.effects,
      adaptive: true,
      created_at: System.system_time(:millisecond)
    }
  end

  @doc """
  Адаптировать качество под текущие условия сети.
  """
  def adapt_to_network(settings, network_stats) do
    bandwidth = network_stats[:bandwidth] || :infinity
    latency = network_stats[:latency] || 0
    packet_loss = network_stats[:packet_loss] || 0

    cond do
      bandwidth < 50_000 or packet_loss > 0.1 ->
        %{settings |
          profile: :economical,
          max_bitrate: 48_000,
          sample_rate: 16_000,
          stereo: false
        }

      bandwidth < 100_000 or packet_loss > 0.05 ->
        %{settings |
          profile: :economical,
          max_bitrate: 96_000,
          sample_rate: 22_050
        }

      bandwidth < 300_000 or latency > 300 ->
        %{settings |
          profile: :balanced,
          max_bitrate: 128_000
        }

      true ->
        settings
    end
  end

  @doc """
  Проверить, можно ли применить эффект с данными настройками.
  """
  def can_apply_effect?(settings, effect_name) do
    effect_name in settings.allowed_effects
  end

  @doc """
  Получить список доступных профилей.
  """
  def list_profiles do
    Map.keys(@quality_profiles)
  end

  @doc """
  Получить описание профиля.
  """
  def describe_profile(profile) do
    case Map.get(@quality_profiles, profile) do
      nil -> {:error, :profile_not_found}
      settings ->
        %{
          name: profile,
          bitrate_kbps: settings.max_bitrate / 1000,
          sample_rate_khz: settings.sample_rate / 1000,
          stereo: settings.stereo,
          latency_ms: settings.max_latency_ms,
          priority: settings.priority,
          effects_count: length(settings.effects)
        }
    end
  end

  @doc """
  Применить ограничения QoS к задаче.
  Устанавливает приоритет процесса, ограничивает использование ресурсов,
  настраивает таймауты и сохраняет настройки для дальнейшего использования.
  """
  def apply_limits(settings) do
    case settings.priority do
      :high ->
        Process.flag(:priority, :high)
      :low ->
        Process.flag(:priority, :low)
      _ ->
        Process.flag(:priority, :normal)
    end

    timeout = calculate_timeout(settings)
    Process.put(:task_timeout, timeout)

    case settings.profile do
      :economical ->
        :erlang.process_flag(:min_heap_size, 1024)
        :erlang.process_flag(:min_bin_vheap_size, 1024)
      :balanced ->
        :erlang.process_flag(:min_heap_size, 2048)
        :erlang.process_flag(:min_bin_vheap_size, 2048)
      :premium ->
        :erlang.process_flag(:min_heap_size, 8192)
        :erlang.process_flag(:min_bin_vheap_size, 8192)
      _ ->
        :erlang.process_flag(:min_heap_size, 2048)
        :erlang.process_flag(:min_bin_vheap_size, 2048)
    end

    Process.put(:qos_settings, settings)

    metadata = %{
      profile: settings.profile,
      priority: settings.priority,
      max_bitrate: settings.max_bitrate,
      sample_rate: settings.sample_rate,
      stereo: settings.stereo,
      max_latency_ms: settings.max_latency_ms,
      max_retries: settings.max_retries,
      started_at: System.system_time(:millisecond)
    }
    Process.put(:qos_metadata, metadata)

    :telemetry.execute([:music_core, :qos, :task_started], %{
      timestamp: System.system_time(:millisecond)
    }, %{
      profile: settings.profile,
      priority: settings.priority
    })

    :ok
  end

  defp calculate_timeout(settings) do
    base_timeout = settings.max_latency_ms * 2
    effects_multiplier = case length(settings.allowed_effects) do
      count when count > 5 -> 3.0
      count when count > 2 -> 1.5
      _ -> 1.0
    end

    priority_multiplier = case settings.priority do
      :high -> 0.8
      :low -> 1.5
      _ -> 1.0
    end

    round(base_timeout * effects_multiplier * priority_multiplier)
  end

  @doc """
  Получить настройки QoS текущего процесса.
  """
  def current_settings do
    Process.get(:qos_settings, get_qos_settings(:balanced))
  end

  @doc """
  Рассчитать таймаут для ретрая на основе настроек.
  """
  def calculate_retry_timeout(settings, attempt) do
    base = 100

    case settings.retry_backoff do
      :none -> 0
      :fixed -> base
      :linear -> base * attempt
      :exponential -> base * (2 ** (attempt - 1))
    end
  end

  @doc """
  Проверить, можно ли ещё ретраить задачу.
  """
  def can_retry?(settings, attempt) do
    attempt <= settings.max_retries
  end

  @doc """
  Получить рекомендуемый формат аудио на основе настроек.
  """
  def recommended_format(settings) do
    %{
      sample_rate: settings.sample_rate,
      channels: if(settings.stereo, do: 2, else: 1),
      bit_depth: 16,
      codec: if(settings.max_bitrate > 256_000, do: :flac, else: :mp3)
    }
  end
end
