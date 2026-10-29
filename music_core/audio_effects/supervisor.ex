defmodule MusicCore.AudioEffects.Supervisor do
  @moduledoc """
  Супервизор для всей подсистемы аудио эффектов.

  Управляет всеми компонентами обработки эффектов:
  1. EffectsManager - основной координатор эффектов
  2. Native.DSP - Rust NIF для высокопроизводительной обработки
  3. FFmpegWrapper - сложные фильтры через FFmpeg
  4. CacheManager - кэширование пресетов и результатов
  5. MetricsCollector - сбор метрик производительности
  6. RealtimeManager - реалтайм обновление эффектов
  7. PresetLoader - загрузка и управление пресетами
  8. GoBridge - интеграция с Go-сервисом обработки
  9. JavaBridge - интеграция с Java Gateway

  Архитектура: Rest for one - если упадёт EffectsManager,
  перезапустятся все зависимые компоненты.
  """
  use Supervisor
  require Logger

  alias MusicCore.{
    AudioEffects.Effects.EffectsManager,
    AudioEffects.Native.DSP.Server,
    AudioEffects.FFmpegWrapper,
    Cache,
    AudioEffects.GoBridge,
    AudioEffects.JavaBridge,
    AudioEffects.Metrics.Collector,
    Cache.RedisClient,
    Workers.CleanupWorker
  }

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    Logger.info("🚀 Starting AudioEffects Supervisor...")

    unless File.regular?("priv/native/libaudio_effects_native.so") do
      Logger.error("NIF library not found! Run 'mix compile' first")
    end

    services_config = Application.get_env(:music_core, :services, [])
    go_config = Keyword.get(services_config, :go_processor, [])
    java_config = Keyword.get(services_config, :java_gateway, [])

    children = [
      # ========== ОСНОВНЫЕ КОМПОНЕНТЫ ==========
      {EffectsManager,
        [
          name: :effects_manager,
          max_parallel_effects: 10,
          fallback_to_software: true,
          timeout: 30000
        ]},

      {Server,
        [
          sample_rate: 48000,
          buffer_size: 4096,
          thread_pool_size: System.schedulers_online() * 2,
          max_processing_time: 5000
        ]},

      # ========== ОБРАБОТКА И ФИЛЬТРЫ ==========
      {FFmpegWrapper,
        [
          ffmpeg_path: System.find_executable("ffmpeg") || "/usr/bin/ffmpeg",
          max_processes: 3,
          timeout: 30000,
          quality_preset: :medium
        ]},

      # ========== ДАННЫЕ И КОНФИГУРАЦИЯ ==========
      {Cache,
        [
          name: :effects_cache,
          max_size_mb: 100,
          ttl_seconds: 3600,
          compression: true,
          persist_to_disk: true
        ]},

      # ========== ИНТЕГРАЦИЯ С ВНЕШНИМИ СЕРВИСАМИ ==========
      {GoBridge,
        [
          host: Keyword.get(go_config, :host, "localhost"),
          port: Keyword.get(go_config, :port, 8080),
          timeout: 10000,
          enabled: true
        ]},

      {JavaBridge,
        [
          host: Keyword.get(java_config, :host, "localhost"),
          port: Keyword.get(java_config, :port, 8081),
          timeout: 8000,
          batch_size: 50
        ]},

      # ========== МОНИТОРИНГ И МЕТРИКИ ==========
      {Collector,
        [
          report_interval: 10000,
          send_to_prometheus: true,
          log_to_file: true,
          metrics: [:processing_time, :memory_usage, :cache_hits, :error_rate],
          supervisor: __MODULE__
        ]},

      # ========== СЛУЖЕБНЫЕ КОМПОНЕНТЫ ==========
      {CleanupWorker,
        [
          interval: 300_000,
          max_age_seconds: 3600
        ]}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  # ========== PUBLIC API ==========
  def status do
    children = Supervisor.which_children(__MODULE__)

    children_data = Enum.map(children, fn {id, pid, type, modules} ->
      dsp_info = if id == Server and pid != nil do
        try do
          GenServer.call(pid, :get_info, 1000)
        catch
          :exit, _ -> %{nif_loaded: false, error: "no response"}
        end
      else
        nil
      end

      memory = case Process.info(pid, :memory) do
        [{:memory, mem}] -> mem
        _ -> 0
      end

      queue_len = case Process.info(pid, :message_queue_len) do
        [{:message_queue_len, q}] -> q
        _ -> 0
      end

      %{
        id: id,
        pid: pid,
        alive: Process.alive?(pid),
        type: type,
        modules: modules,
        memory: memory,
        message_queue_len: queue_len,
        dsp_info: dsp_info
      }
    end)
    |> Enum.sort_by(&to_string(&1.id))

    :telemetry.execute([:music_core, :audio_effects, :supervisor, :status], %{
      total_children: length(children_data),
      alive_children: Enum.count(children_data, & &1.alive),
      total_memory: Enum.reduce(children_data, 0, &(&2 + (&1.memory || 0)))
    }, %{})

    children_data
  end

  def restart_child(child_id) do
    case Supervisor.restart_child(__MODULE__, child_id) do
      {:ok, pid} ->
        Logger.info("Restarted child #{child_id} with PID #{inspect(pid)}")
        {:ok, pid}

      {:ok, pid, _info} ->
        Logger.info("Restarted child #{child_id} with PID #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to restart child #{child_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def resource_stats do
    children = status()

    %{
      total_memory: Enum.reduce(children, 0, &(&2 + &1.memory)),
      total_processes: length(children),
      alive_processes: Enum.count(children, & &1.alive),
      avg_queue_len: Enum.reduce(children, 0, &(&2 + &1.message_queue_len)) / max(length(children), 1)
    }
  end

  def reload_config do
    children = Supervisor.which_children(__MODULE__)
    config_children = ["RedisClient"]

    results = Enum.map(children, fn {id, _pid, _type, _modules} ->
      if Enum.any?(config_children, &String.contains?(to_string(id), &1)) do
        restart_child(id)
      else
        {:skipped, id}
      end
    end)

    {:ok, results}
  end

  def graceful_shutdown(timeout \\ 30_000) do
    Logger.info("Gracefully shutting down AudioEffects subsystem...")

    if function_exported?(EffectsManager, :disable_new_requests, 0) do
      EffectsManager.disable_new_requests()
    end

    Process.sleep(1000)
    Supervisor.stop(__MODULE__, :normal, timeout)
  end

  def health_check do
    children = status()
    healthy = Enum.all?(children, & &1.alive)
    total_children = length(children)
    alive_children = Enum.count(children, & &1.alive)
    total_memory = Enum.reduce(children, 0, &(&2 + &1.memory))
    total_queue = Enum.reduce(children, 0, &(&2 + &1.message_queue_len))

    %{
      healthy: healthy,
      details: %{
        total_children: total_children,
        alive_children: alive_children,
        total_memory_kb: div(total_memory, 1024),
        avg_queue_len: if(total_children > 0, do: total_queue / total_children, else: 0.0)
      },
      timestamp: DateTime.utc_now()
    }
  end
end
