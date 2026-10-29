defmodule MusicCore.QueueManager do
  @moduledoc """
  Основной модуль для управления аудио очередями и стримами.

  Координирует работу между процессором, менеджером стримов и Discord клиентом.
  """

  use GenServer
  require Logger

  alias MusicCore.{Metrics, AudioStreaming.Processor, AudioStream.Manager, AudioStreaming.DiscordClient}

  # ========== Клиентский API ==========

  @doc """
  Запускает супервизор очередей.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Добавляет трек в очередь гильдии.
  """
  @spec add_track(String.t(), String.t(), map()) :: {:ok, integer()} | {:error, term()}
  def add_track(guild_id, track_url, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:add_track, guild_id, track_url, metadata})
  end

  @doc """
  Запускает новый аудио поток из очереди.
  """
  @spec start_stream(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def start_stream(guild_id, stream_id \\ nil) do
    GenServer.call(__MODULE__, {:start_stream, guild_id, stream_id})
  end

  @doc """
  Останавливает аудио поток.
  """
  @spec stop_stream(String.t()) :: :ok | {:error, term()}
  def stop_stream(stream_id) do
    GenServer.call(__MODULE__, {:stop_stream, stream_id})
  end

  @doc """
  Пропускает текущий трек.
  """
  @spec skip_track(String.t()) :: {:ok, map()} | {:error, term()}
  def skip_track(guild_id) do
    GenServer.call(__MODULE__, {:skip_track, guild_id})
  end

  @doc """
  Очищает очередь гильдии.
  """
  @spec clear_queue(String.t()) :: :ok
  def clear_queue(guild_id) do
    GenServer.call(__MODULE__, {:clear_queue, guild_id})
  end

  @doc """
  Перемешивает очередь гильдии.
  """
  @spec shuffle_queue(String.t()) :: :ok
  def shuffle_queue(guild_id) do
    GenServer.call(__MODULE__, {:shuffle_queue, guild_id})
  end

  @doc """
  Получает текущую очередь гильдии.
  """
  @spec get_queue(String.t()) :: list()
  def get_queue(guild_id) do
    GenServer.call(__MODULE__, {:get_queue, guild_id})
  end

  @doc """
  Получает текущий статус воспроизведения.
  """
  @spec get_status(String.t()) :: map()
  def get_status(guild_id) do
    GenServer.call(__MODULE__, {:get_status, guild_id})
  end

  @doc """
  Применяет эффекты к активному потоку.
  """
  @spec apply_effects(String.t(), list()) :: :ok | {:error, term()}
  def apply_effects(stream_id, effects) do
    GenServer.call(__MODULE__, {:apply_effects, stream_id, effects})
  end

  @doc """
  Получает статус всех активных стримов.
  """
  @spec get_streams_status() :: list()
  def get_streams_status do
    GenServer.call(__MODULE__, :get_streams_status)
  end

  # ========== Сервер ==========

  def init(opts) do
    state = %{
      queues: %{},           # guild_id => queue
      current_tracks: %{},   # guild_id => current_track
      stream_ids: %{},       # guild_id => stream_id
      timers: %{},           # guild_id => timer_ref
      config: %{
        max_queue_size: Keyword.get(opts, :max_queue_size, 100),
        auto_play: Keyword.get(opts, :auto_play, true),
        reconnect_attempts: Keyword.get(opts, :reconnect_attempts, 3)
      }
    }

    Logger.info("QueueManager started")
    {:ok, state}
  end

  def handle_call({:add_track, guild_id, track_url, metadata}, state) do
    queue = Map.get(state.queues, guild_id, [])
    track = %{
      id: generate_track_id(),
      url: track_url,
      metadata: metadata,
      added_at: DateTime.utc_now()
    }

    if length(queue) >= state.config.max_queue_size do
      {:reply, {:error, :queue_full}, state}
    else
      new_queue = queue ++ [track]
      new_state = put_in(state, [:queues, guild_id], new_queue)

      Metrics.queue_track_added(guild_id)
      Logger.info("Track added to queue for guild #{guild_id}. Queue size: #{length(new_queue)}")

      # Автоматически запускаем воспроизведение если ничего не играет
      if state.config.auto_play and not Map.has_key?(state.current_tracks, guild_id) do
        Process.send_after(self(), {:start_next, guild_id}, 100)
      end

      {:reply, {:ok, length(new_queue)}, new_state}
    end
  end

  def handle_call({:start_stream, guild_id, stream_id}, state) do
    queue = Map.get(state.queues, guild_id, [])

    if queue == [] do
      {:reply, {:error, :empty_queue}, state}
    else
      [track | rest_queue] = queue
      actual_stream_id = stream_id || generate_stream_id()

      case Manager.register_stream(actual_stream_id, guild_id, %{track_url: track.url}) do
        {:ok, stream_info} ->
          case start_playback(guild_id, actual_stream_id, track, state) do
            {:ok, _} ->
              new_state = state
              |> put_in([:queues, guild_id], rest_queue)
              |> put_in([:current_tracks, guild_id], track)
              |> put_in([:stream_ids, guild_id], actual_stream_id)

              Metrics.stream_started(actual_stream_id, guild_id, %{track: track.url})
              Logger.info("Stream started: #{actual_stream_id} for guild #{guild_id}")

              # Запускаем таймер для след. трека (если нужно)
              if rest_queue != [] do
                timer = Process.send_after(self(), {:start_next, guild_id}, 1000)
                new_state = put_in(new_state, [:timers, guild_id], timer)
                {:reply, {:ok, stream_info}, new_state}
              else
                {:reply, {:ok, stream_info}, new_state}
              end

            error ->
              {:reply, error, state}
          end

        error ->
          {:reply, error, state}
      end
    end
  end

  def handle_call({:stop_stream, stream_id}, state) do
    case find_guild_by_stream_id(state, stream_id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}

      guild_id ->
        case Manager.get_stream_info(stream_id) do
          {:ok, stream_info} ->
            DiscordClient.stop_track(stream_info.guild_id)
            Manager.unregister_stream(stream_id)
            Processor.stop_stream(stream_id)

            # Очищаем состояние
            new_state = state
            |> put_in([:current_tracks, guild_id], nil)
            |> put_in([:stream_ids, guild_id], nil)

            # Отменяем таймер
            case Map.get(state.timers, guild_id) do
              nil -> :ok
              tref -> Process.cancel_timer(tref)
            end
            new_state = put_in(new_state, [:timers, guild_id], nil)

            Metrics.stream_stopped(stream_id, guild_id, 0, %{reason: :stopped})
            Logger.info("Stream stopped: #{stream_id} for guild #{guild_id}")

            # Запускаем следующий трек если есть
            queue = Map.get(state.queues, guild_id, [])
            if queue != [] do
              Process.send_after(self(), {:start_next, guild_id}, 500)
            end

            {:reply, :ok, new_state}

          error ->
            {:reply, error, state}
        end
    end
  end

  def handle_call({:skip_track, guild_id}, state) do
    case Map.get(state.stream_ids, guild_id) do
      nil ->
        {:reply, {:error, :no_active_stream}, state}

      stream_id ->
        Metrics.track_skipped(guild_id)
        Logger.info("Track skipped for guild #{guild_id}")

        # Останавливаем текущий и запускаем следующий
        Manager.unregister_stream(stream_id)
        Processor.stop_stream(stream_id)

        new_state = state
        |> put_in([:current_tracks, guild_id], nil)
        |> put_in([:stream_ids, guild_id], nil)

        queue = Map.get(state.queues, guild_id, [])
        if queue != [] do
          Process.send_after(self(), {:start_next, guild_id}, 100)
        end

        {:reply, {:ok, %{skipped: true}}, new_state}
    end
  end

  def handle_call({:clear_queue, guild_id}, state) do
    new_state = put_in(state, [:queues, guild_id], [])
    Metrics.queue_cleared(guild_id)
    Logger.info("Queue cleared for guild #{guild_id}")
    {:reply, :ok, new_state}
  end

  def handle_call({:shuffle_queue, guild_id}, state) do
    queue = Map.get(state.queues, guild_id, [])
    shuffled = Enum.shuffle(queue)
    new_state = put_in(state, [:queues, guild_id], shuffled)
    Metrics.queue_shuffled(guild_id)
    Logger.info("Queue shuffled for guild #{guild_id}")
    {:reply, :ok, new_state}
  end

  def handle_call({:get_queue, guild_id}, state) do
    queue = Map.get(state.queues, guild_id, [])
    {:reply, queue, state}
  end

  def handle_call({:get_status, guild_id}, state) do
    current_track = Map.get(state.current_tracks, guild_id)
    queue = Map.get(state.queues, guild_id, [])
    stream_id = Map.get(state.stream_ids, guild_id)
    is_playing = stream_id != nil

    status = %{
      guild_id: guild_id,
      is_playing: is_playing,
      current_track: current_track,
      queue_size: length(queue),
      queue_tracks: queue,
      stream_id: stream_id
    }

    {:reply, status, state}
  end

  def handle_call({:apply_effects, stream_id, effects}, state) do
    case Manager.get_stream_info(stream_id) do
      {:ok, stream_info} ->
        case Processor.process_audio(stream_id, "audio_data", effects) do
          {:ok, _} ->
            Metrics.effect_applied("effects_batch", stream_id, %{count: length(effects)})
            {:reply, :ok, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :stream_not_found}, state}
    end
  end

  def handle_call(:get_streams_status, state) do
    active = for {guild_id, stream_id} <- state.stream_ids, stream_id != nil do
      %{
        guild_id: guild_id,
        stream_id: stream_id,
        current_track: Map.get(state.current_tracks, guild_id),
        queue_size: length(Map.get(state.queues, guild_id, []))
      }
    end

    {:reply, active, state}
  end

  # ========== Обработка сообщений ==========

  def handle_info({:start_next, guild_id}, state) do
    # Отменяем старый таймер
    case Map.get(state.timers, guild_id) do
      nil -> :ok
      tref -> Process.cancel_timer(tref)
    end

    case start_stream(guild_id, nil) do
      {:ok, _} ->
        Logger.info("Started next track for guild #{guild_id}")
      error ->
        Logger.error("Failed to start next track for guild #{guild_id}: #{inspect(error)}")
    end

    new_state = put_in(state, [:timers, guild_id], nil)
    {:noreply, new_state}
  end

  def handle_info({:track_ended, guild_id}, state) do
    Logger.info("Track ended for guild #{guild_id}")
    Process.send_after(self(), {:start_next, guild_id}, 500)
    {:noreply, state}
  end

  # ========== Приватные функции ==========

  defp start_playback(guild_id, stream_id, track, state) do
    case DiscordClient.connect_voice(guild_id, nil, nil, nil) do
      {:ok, _} ->
        case DiscordClient.play_track(guild_id, %{track: track.url}) do
          {:ok, _} ->
            # Запускаем обработку аудио
            Task.start(fn ->
              process_audio_stream(stream_id, guild_id, track.url, track.metadata[:effects] || [])
            end)
            {:ok, %{stream_id: stream_id, track: track}}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp process_audio_stream(stream_id, guild_id, track_url, effects) do
    try do
      case download_track(track_url) do
        {:ok, audio_data} ->
          case Processor.process_audio(stream_id, audio_data, effects) do
            {:ok, processed_data} ->
              Logger.info("Audio processing completed for stream #{stream_id}")
              send_to_discord(guild_id, processed_data)
              send(self(), {:track_ended, guild_id})

            {:error, reason} ->
              Logger.error("Audio processing failed for stream #{stream_id}: #{inspect(reason)}")
              send(self(), {:track_ended, guild_id})
          end

        {:error, reason} ->
          Logger.error("Track download failed for stream #{stream_id}: #{inspect(reason)}")
          send(self(), {:track_ended, guild_id})
      end
    rescue
      error ->
        Logger.error("Exception in audio stream processing #{stream_id}: #{inspect(error)}")
        send(self(), {:track_ended, guild_id})
    end
  end

  defp download_track(track_url) do
    try do
      case Req.get(track_url, timeout: 30_000) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          {:ok, body}
        {:error, reason} ->
          Logger.error("Download failed: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      _ -> {:error, :download_failed}
    end
  end

  defp send_to_discord(guild_id, audio_data) do
    DiscordClient.send_audio(guild_id, audio_data)
  end

  defp find_guild_by_stream_id(state, stream_id) do
    Enum.find_value(state.stream_ids, fn {guild_id, sid} ->
      if sid == stream_id, do: guild_id
    end)
  end

  defp generate_track_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "track_#{timestamp}_#{random}"
  end

  defp generate_stream_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "stream_#{timestamp}_#{random}"
  end
end
