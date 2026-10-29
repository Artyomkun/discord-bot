defmodule MusicCore.Metrics do
  @moduledoc """
  Модуль для сбора и обработки метрик MusicCore.
  """

  use GenServer
  require Logger
  import MusicCore.Telemetry.Metrics
  import Ecto.Query.WindowAPI
  import Ecto.Query.API

  @type metric_name :: atom()
  @type metric_value :: term()
  @type tags :: map()

  # API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    :telemetry.attach_many("music-core-handler", [
      [:music_core, :audio, :processed],
      [:music_core, :stream, :started],
      [:music_core, :stream, :stopped]
    ], &handle_event/4, nil)

    {:ok, opts}
  end

  def handle_event(event, measurements, metadata, config) do
    if Kernel.==(Mix.env(), :dev) do
      IO.inspect({event, measurements, metadata})
    end
    :ok
  end

  @doc """
  Записать метрику.
  """
  @spec record(metric_name(), metric_value(), tags()) :: :ok
  def record(name, value, tags \\ %{}) do
    :telemetry.execute([:music_core, :metrics, name], %{value: value}, tags)
    log_important_metrics(name, value, tags)
    :ok
  end

  @doc """
  Записать время выполнения.
  """
  @spec timing(metric_name(), non_neg_integer(), tags()) :: :ok
  def timing(name, time_ms, tags \\ %{}) do
    record(name, time_ms, Map.put(tags, :unit, :ms))
  end

  @doc """
  Записать ошибку.
  """
  @spec error(metric_name(), term(), tags()) :: :ok
  def error(name, error, tags \\ %{}) do
    record(name, %{error: inspect(error)}, Map.put(tags, :type, :error))
  end

  @doc """
  Получить список метрик.
  """
  @spec metrics() :: list()
  def metrics do
    [
      API.counter("music_core.audio.streams_started"),
      API.counter("music_core.audio.streams_stopped"),
      API.counter("music_core.audio.processing_errors"),
      API.counter("music_core.effects.applied"),
      API.counter("music_core.queue.tracks_added"),
      API.counter("music_core.queue.tracks_removed"),

      Metrics.distribution("music_core.audio.processing_duration",
        measurement: :duration,
        unit: {:native, :millisecond}
      ),
      Metrics.distribution("music_core.audio.stream_duration",
        measurement: :duration,
        unit: {:native, :second}
      ),

      WindowAPI.sum("music_core.audio.bytes_processed"),

      WindowAPI.last_value("music_core.system.active_streams"),
      WindowAPI.last_value("music_core.system.queue_size"),
      WindowAPI.last_value("music_core.cache.size")
    ]
  end

  # Специфические метрики

  @doc "Записать метрику начала обработки аудио"
  @spec audio_processing_start(String.t(), map()) :: :ok
  def audio_processing_start(stream_id, metadata \\ %{}) do
    record(:audio_processing_start, 1, Map.put(metadata, :stream_id, stream_id))
  end

  @doc "Записать метрику окончания обработки аудио"
  @spec audio_processing_stop(String.t(), non_neg_integer(), map()) :: :ok
  def audio_processing_stop(stream_id, duration_ms, metadata \\ %{}) do
    timing(:audio_processing_duration, duration_ms, Map.put(metadata, :stream_id, stream_id))
    record(:audio_processing_stop, 1, Map.put(metadata, :stream_id, stream_id))
  end

  @doc "Записать метрику ошибки обработки аудио"
  @spec audio_processing_error(String.t(), term(), map()) :: :ok
  def audio_processing_error(stream_id, error, metadata \\ %{}) do
    error(:audio_processing_error, error, Map.put(metadata, :stream_id, stream_id))
  end

  @doc "Записать метрику начала стрима"
  @spec stream_started(String.t(), String.t(), map()) :: :ok
  def stream_started(stream_id, guild_id, metadata \\ %{}) do
    Metrics.increment(:streams_started, 1, Map.merge(metadata, %{stream_id: stream_id, guild_id: guild_id}))
  end

  @doc "Записать метрику окончания стрима"
  @spec stream_stopped(String.t(), String.t(), non_neg_integer(), map()) :: :ok
  def stream_stopped(stream_id, guild_id, duration_sec, metadata \\ %{}) do
    timing(:stream_duration, duration_sec, Map.merge(metadata, %{stream_id: stream_id, guild_id: guild_id}))
    Metrics.increment(:streams_stopped, 1, Map.merge(metadata, %{stream_id: stream_id, guild_id: guild_id}))
  end

  @doc "Записать метрику применения эффекта"
  @spec effect_applied(String.t(), String.t(), map()) :: :ok
  def effect_applied(effect_name, stream_id, metadata \\ %{}) do
    Metrics.increment(:effects_applied, 1, Map.merge(metadata, %{effect: effect_name, stream_id: stream_id}))
  end

  @doc "Записать метрику добавления трека в очередь"
  @spec queue_track_added(String.t()) :: :ok
  def queue_track_added(guild_id) do
    Metrics.increment(:queue_tracks_added, 1, %{guild_id: guild_id})
  end

  @doc "Записать метрику удаления трека из очереди"
  @spec queue_track_removed(String.t()) :: :ok
  def queue_track_removed(guild_id) do
    Metrics.increment(:queue_tracks_removed, 1, %{guild_id: guild_id})
  end

  @doc "Записать метрику очистки очереди"
  @spec queue_cleared(String.t()) :: :ok
  def queue_cleared(guild_id) do
    Metrics.increment(:queue_cleared, 1, %{guild_id: guild_id})
  end

  @doc "Записать метрику перемешивания очереди"
  @spec queue_shuffled(String.t()) :: :ok
  def queue_shuffled(guild_id) do
    Metrics.increment(:queue_shuffled, 1, %{guild_id: guild_id})
  end

  @doc "Записать метрику пропуска трека"
  @spec track_skipped(String.t()) :: :ok
  def track_skipped(guild_id) do
    Metrics.increment(:tracks_skipped, 1, %{guild_id: guild_id})
  end

  @doc "Записать метрику начала трека"
  @spec track_started(String.t(), map()) :: :ok
  def track_started(guild_id, track_metadata) do
    record(:track_started, 1, Map.put(track_metadata, :guild_id, guild_id))
  end

  # Приватные функции

  defp log_important_metrics(:audio_processing_error, value, tags) do
    Logger.warning("Audio processing error in stream #{tags[:stream_id]}: #{inspect(value)}")
  end

  defp log_important_metrics(:streams_started, value, tags) do
    Logger.info("Stream started: #{tags[:stream_id]} for guild #{tags[:guild_id]}")
  end

  defp log_important_metrics(:streams_stopped, value, tags) do
    Logger.info("Stream stopped: #{tags[:stream_id]} for guild #{tags[:guild_id]}")
  end

  defp log_important_metrics(name, value, tags) do
    :ok
  end
end
