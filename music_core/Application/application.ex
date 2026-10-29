defmodule MusicCore.Application.Application do
  @moduledoc false
  use Application

  require Logger
  alias MusicCore.AudioStream.{PeriodicCleanup, Manager}
  alias AudioStreaming.{Processor, FFmpeg}
  alias MusicCore.Services.{JavaGateway, GoProcessor}
  alias MusicCore.Cache.{Database, RedisClient}
  alias ElixirServer.{Metrics, Pool, Protocol}
  alias ElixirClient.Client.{ConnectionPool, RoundRobin, ServiceDiscovery, AudioProcessor}
  alias MusicCore.{
    AudioEffects.Effects.EffectsManager,
    AudioEffects.Supervisor,
    AudioEffects.Metrics.Collector,
    AudioEffects.Processor.Worker,
    AudioEffects.Processor.Processor,
    AudioStream.PeriodicCleanup,
    AudioStream.Manager,
    AudioStream.Processor,
    AudioStreaming.Processor,
    AudioStreaming.FFmpeg,
    AudioStreaming.DiscordClient,
    AudioStreaming.Backpressure,
    AudioStreaming.QualityManager,
    AudioStreaming.QueueManager,
    AudioStreaming.TaskSupervisor,
    Workers.CleanupWorker,
    ExternalAPIs.Manager,
    WebSocket.Endpoint,
    WebSockAdapter,
    TelemetryExporter,
    TelemetryHandler,
    HealthCheck,
    Telemetry,
    Metrics,
    Router,
    Config,
    Cache,
    Buffer,
    ServiceRegistry,
    CircuitBreaker,
    QueueManager,
    Reports,
    AudioCache
  }

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :ssl, :inets, :ecto],
      mod: {MusicCore.Application.Application, []}
    ]
  end

  @impl true
  def start(_type, _args) do
    :prometheus_counter.new([
      name: :dsp_nif_load_success,
      help: "DSP NIF load success count"
    ])
    :prometheus_counter.new([
      name: :dsp_nif_load_error,
      labels: [:reason],
      help: "DSP NIF load error count"
    ])
    setup_telemetry()
    config = Config.load()
    :telemetry.attach_many(
      "music-core-dsp-handler",
      [
        [:music_core, :dsp, :nif, :loaded],
        [:music_core, :dsp, :call],
        [:music_core, :dsp, :terminate],
        [:music_core, :audio_effects, :supervisor, :status],
        [:music_core, :audio_effects, :metrics]
      ],
      &TelemetryHandler.handle_event/4,
      nil
    )

    children = [
      # ========== БАЗА ДАННЫХ (ПЕРВОЙ!) ==========
      MusicCore.Repo,
      Buffer,

      # ========== REDIS ==========
      {Redix, name: :redix, host: "localhost", port: 6379},

      # ========== КЭШ ==========
      {ConCache, [name: :effects_cache, ttl_check_interval: :timer.seconds(30), global_ttl: :timer.hours(24), acquire_lock_timeout: 5_000]},
      {ConCache, [name: :audio_cache, ttl_check_interval: :timer.seconds(5), global_ttl: :timer.hours(1), acquire_lock_timeout: 10_000]},

      # ========== МЕТРИКИ ==========
      {ElixirServer.Metrics, []},
      {ElixirClient.Client.Metrics, []},
      {Metrics, []},
      {HealthCheck, []},
      {TelemetryExporter, []},

      # ========== gRPC ==========
      {ElixirServer.Server.Supervisor, {ElixirServer.Protocol, Application.get_env(:elixir_server, :grpc_port, 50_050)}},
      {ElixirServer.Server.ConnectionPool, []},
      {ElixirServer.Pool, []},
      {ElixirClient.Client.ConnectionPool, []},
      {ElixirClient.Client.Pool, []},
      {ElixirClient.Client.PubSub, []},
      {ElixirClient.Client.RoundRobin, []},
      {ElixirClient.Client.ServiceDiscovery, []},
      {ElixirClient.Client.AudioProcessor, []},

      # ========== HTTP МЕТРИКИ ==========
      {Plug.Cowboy, scheme: :http, plug: ElixirServer.MetricsHTTP, port: 8080},

      # ========== OBAN ==========
      {Oban, oban_config()},

      # ========== АУДИО ОБРАБОТКА ==========
      {EffectsManager, []},
      {PeriodicCleanup, [interval: config[:audio_processing][:cleanup_interval] || 300_000]},

      # ========== АУДИО ПОТОКИ ==========
      {Processor,
        [
          name: :audio_processor,
          max_concurrent: config[:audio_processing][:max_concurrent_streams] || 10,
          queue_size: config[:audio_processing][:max_queue_size] || 100
        ]
      },
      {Manager, []},
      {FFmpeg,
        [
          path: config[:ffmpeg][:path] || "ffmpeg",
          buffer_size: config[:ffmpeg][:buffer_size] || 8192,
          sample_rate: config[:ffmpeg][:sample_rate] || 48000,
          channels: config[:ffmpeg][:channels] || 2,
          bitrate: config[:ffmpeg][:bitrate] || 128,
          codec: config[:ffmpeg][:codec] || "libopus",
          format: config[:ffmpeg][:format] || "opus",
          reconnect_attempts: config[:ffmpeg][:reconnect_attempts] || 5,
          reconnect_delay: config[:ffmpeg][:reconnect_delay] || 1_000,
          frame_buffer: config[:ffmpeg][:frame_buffer] || 5000, opus_quality: config[:ffmpeg][:opus_quality] || 4
        ]
      },

      # ========== ВНЕШНИЕ API ==========
      {ExternalAPIs.Manager, []},

      # ========== HTTP ==========
      {Plug.Cowboy,
        [
          scheme: :http,
          plug: Router,
          options: [
            port: config[:http_port] || 4000,
            protocol_options: [
              idle_timeout: 30_000,
              request_timeout: 15_000, max_keepalive: 100
            ],
            compress: true
          ]
        ]
      },
      {MusicCore.WebSocket.Endpoint, []},

      # ========== СУПЕРВИЗОР ==========
      Supervisor
    ]

    opts = [
      strategy: :one_for_one,
      name: Supervisor,
      max_restarts: 10,
      max_seconds: 5,
      intensity: 3
    ]

    case Supervisor.start_link(opts) do
      {:ok, sup} = result ->
        Logger.info("""
        MusicCore Application started successfully
        HTTP Port: #{config[:http_port] || 4000}
        FFmpeg: #{config[:ffmpeg][:path]} (buffer: #{config[:ffmpeg][:buffer_size]}, rate: #{config[:ffmpeg][:sample_rate]}Hz, channels: #{config[:ffmpeg][:channels]}, codec: #{config[:ffmpeg][:codec]})
        Environment: #{Mix.env()}
        """)

        schedule_background_tasks()

        result

      {:error, reason} ->
        Logger.error("Failed to start MusicCore: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def prep_stop(state) do
    Logger.info("Gracefully stopping MusicCore application...")

    Router.disable_new_requests()

    active_streams = Manager.active_streams_count()
    if active_streams > 0 do
      Logger.info("Stopping #{active_streams} active audio streams")
      Processor.graceful_shutdown(timeout: 30_000)
    end

    EffectsManager.persist_state()
    Buffer.stop()

    Logger.info("MusicCore stopped gracefully")
    state
  end

  @impl true
  def config_change(changed, new, removed) do
    Logger.info("Configuration changed",
      changed: inspect(changed),
      removed: inspect(removed)
    )

    if Map.has_key?(changed, :ffmpeg) do
      case Processor.reconfigure(new[:ffmpeg]) do
        :ok ->
          Logger.info("FFmpeg reconfigured successfully")
        {:error, reason} ->
          Logger.error("Failed to reconfigure FFmpeg: #{inspect(reason)}")
      end
    end

    if Map.has_key?(changed, :http_port) do
      new_port = new[:http_port]
      Logger.info("HTTP port will change to #{new_port} on next restart")
      send(self(), {:port_changed, new_port})
    end

    :ok
  end

  # ========== PRIVATE ==========

  defp setup_telemetry do
    :telemetry.attach_many("music-core-telemetry", [
      [:music_core, :supervisor, :init],
      [:supervisor, :child_restart],
      [:oban, :job, :start],
      [:oban, :job, :stop],
      [:plug_cowboy, :request, :start],
      [:plug_cowboy, :request, :stop],
      [:music_core, :audio, :processing_start],
      [:music_core, :audio, :processing_stop]
    ], &Telemetry.handle_event/4, nil)
  end

  defp schedule_background_tasks do
    Process.send_after(self(), :cleanup_cache, 60_000)
    Process.send_after(self(), :check_ffmpeg_availability, 5_000)
    Process.send_after(self(), :collect_metrics, 15_000)
  end

  # ========== HANDLE_INFO ==========

  @impl true
  def handle_info(:cleanup_cache, state) do
    Task.start(fn -> Cache.cleanup() end)
    Process.send_after(self(), :cleanup_cache, 60_000)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_ffmpeg_availability, state) do
    config = Config.load()
    ffmpeg_path = config[:ffmpeg][:path] || "ffmpeg"

    case System.find_executable(ffmpeg_path) do
      nil ->
        Logger.error("FFmpeg not found at #{ffmpeg_path}")
        {:noreply, state}
      path ->
        Logger.info("✅ FFmpeg found at #{path}")
        :persistent_term.put(:ffmpeg_path, path)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    collect_metrics()
    Process.send_after(self(), :collect_metrics, 30_000)
    {:noreply, state}
  end

  defp collect_metrics do
    stats = %{
      audio_cache_size: ConCache.size(:audio_cache),
      effects_cache_size: ConCache.size(:effects_cache),
      active_streams: Manager.active_streams_count(),
      queue_size: Processor.queue_size(),
      processed_total: Processor.stats().total_processed
    }

    Metrics.record(:system_stats, stats)

    if stats.queue_size > 50 do
      Logger.warning("High queue size: #{stats.queue_size}")
    end
  end

  defp oban_config do
    [
      name: Oban,
      repo: Buffer,
      plugins: [
        {Oban.Plugins.Pruner, max_age: :timer.hours(24)},
        {Oban.Plugins.Cron,
          crontab: [
            {"*/5 * * * *", CleanupWorker}
          ]}
      ],
      queues: [
        audio_processing: 10,
        effects_processing: 5,
        notifications: 2
      ]
    ]
  end
end
