defmodule MusicCore.AudioStreaming.QueueManager do
  @moduledoc """
  Менеджер очередей воспроизведения для разных гильдий
  """

  use GenServer
  require Logger

  alias MusicCore.{Metrics, Cache}

  # API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Управление очередью для гильдии
  """
  def manage_queue(guild_id, action, track \\ nil) do
    GenServer.call(__MODULE__, {:manage_queue, guild_id, action, track})
  end

  @doc """
  Получить очередь для гильдии
  """
  def get_queue(guild_id) do
    GenServer.call(__MODULE__, {:get_queue, guild_id})
  end

  @doc """
  Очистить очередь для гильдии
  """
  def clear_queue(guild_id) do
    GenServer.call(__MODULE__, {:clear_queue, guild_id})
  end

  @doc """
  Перемешать очередь для гильдии
  """
  def shuffle_queue(guild_id) do
    GenServer.call(__MODULE__, {:shuffle_queue, guild_id})
  end

  # Server callbacks
  def init(_opts) do
    state = %{
      queues: %{},  # guild_id => queue
      current_tracks: %{},  # guild_id => current_track
      history: %{}  # guild_id => played_tracks
    }

    {:ok, state}
  end

  def handle_call({:manage_queue, guild_id, action, track}, _from, state) do
    case action do
      "add" when track != nil ->
        new_state = add_to_queue(state, guild_id, track)
        Metrics.queue_track_added(guild_id)
        {:reply, {:ok, %{action: "add", track: track, position: get_queue_size(state, guild_id)}}, new_state}

      "remove" when track != nil ->
        case remove_from_queue(state, guild_id, track) do
          {:ok, removed_track, new_state} ->
            Metrics.queue_track_removed(guild_id)
            {:reply, {:ok, %{action: "remove", removed_track: removed_track}}, new_state}

          {:error, reason, new_state} ->
            {:reply, {:error, reason}, new_state}
        end

      "clear" ->
        new_state = clear_guild_queue(state, guild_id)
        Metrics.queue_cleared(guild_id)
        {:reply, {:ok, %{action: "clear", cleared_count: get_queue_size(state, guild_id)}}, new_state}

      "shuffle" ->
        new_state = shuffle_guild_queue(state, guild_id)
        Metrics.queue_shuffled(guild_id)
        {:reply, {:ok, %{action: "shuffle"}}, new_state}

      "next" ->
        case get_next_track(state, guild_id) do
          {:ok, next_track, new_state} ->
            Metrics.track_started(guild_id, next_track)
            {:reply, {:ok, %{action: "next", track: next_track}}, new_state}

          {:error, :empty_queue, new_state} ->
            {:reply, {:error, "Queue is empty"}, new_state}
        end

      "skip" ->
        case skip_current_track(state, guild_id) do
          {:ok, skipped_track, new_state} ->
            Metrics.track_skipped(guild_id)
            {:reply, {:ok, %{action: "skip", skipped_track: skipped_track}}, new_state}

          {:error, reason, new_state} ->
            {:reply, {:error, reason}, new_state}
        end

      _ ->
        {:reply, {:error, "Unknown action: #{action}"}, state}
    end
  end

  def handle_call({:get_queue, guild_id}, _from, state) do
    queue = get_guild_queue(state, guild_id)
    current = Map.get(state.current_tracks, guild_id)

    result = %{
      current_track: current,
      queue: :queue.to_list(queue),
      size: :queue.len(queue),
      guild_id: guild_id
    }

    {:reply, result, state}
  end

  def handle_call({:clear_queue, guild_id}, _from, state) do
    new_state = clear_guild_queue(state, guild_id)
    Metrics.queue_cleared(guild_id)
    {:reply, :ok, new_state}
  end

  def handle_call({:shuffle_queue, guild_id}, _from, state) do
    new_state = shuffle_guild_queue(state, guild_id)
    Metrics.queue_shuffled(guild_id)
    {:reply, :ok, new_state}
  end

  # Приватные функции

  defp get_guild_queue(state, guild_id) do
    Map.get_lazy(state.queues, guild_id, fn -> :queue.new() end)
  end

  defp get_queue_size(state, guild_id) do
    state.queues
    |> Map.get(guild_id, :queue.new())
    |> :queue.len()
  end

  defp add_to_queue(state, guild_id, track) do
    queue = get_guild_queue(state, guild_id)
    new_queue = :queue.in(track, queue)

    new_queues = Map.put(state.queues, guild_id, new_queue)
    %{state | queues: new_queues}
  end

  defp remove_from_queue(state, guild_id, track_identifier) do
    queue = get_guild_queue(state, guild_id)
    list = :queue.to_list(queue)

    # Ищем трек по идентификатору (может быть индексом или ID)
    case remove_track_from_list(list, track_identifier) do
      {:ok, removed_track, new_list} ->
        new_queue = :queue.from_list(new_list)
        new_queues = Map.put(state.queues, guild_id, new_queue)
        new_state = %{state | queues: new_queues}
        {:ok, removed_track, new_state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp remove_track_from_list(list, identifier) do
    case Integer.parse(identifier) do
      {index, ""} when index >= 0 and index < length(list) ->
        # Удаление по индексу
        {removed, rest} = List.pop_at(list, index)
        {:ok, removed, rest}

      _ ->
        # Поиск по ID или названию
        case Enum.find_index(list, fn track ->
          track["id"] == identifier or track["title"] == identifier
        end) do
          nil ->
            {:error, "Track not found"}

          index ->
            {removed, rest} = List.pop_at(list, index)
            {:ok, removed, rest}
        end
    end
  end

  defp clear_guild_queue(state, guild_id) do
    new_queues = Map.delete(state.queues, guild_id)
    %{state | queues: new_queues}
  end

  defp shuffle_guild_queue(state, guild_id) do
    queue = get_guild_queue(state, guild_id)
    list = :queue.to_list(queue)

    if length(list) > 1 do
      shuffled = Enum.shuffle(list)
      new_queue = :queue.from_list(shuffled)
      new_queues = Map.put(state.queues, guild_id, new_queue)
      %{state | queues: new_queues}
    else
      state
    end
  end

  defp get_next_track(state, guild_id) do
    queue = get_guild_queue(state, guild_id)

    case :queue.out(queue) do
      {{:value, track}, new_queue} ->
        # Перемещаем текущий трек в историю
        current = Map.get(state.current_tracks, guild_id)
        new_history = add_to_history(state.history, guild_id, current)

        new_queues = Map.put(state.queues, guild_id, new_queue)
        new_current_tracks = Map.put(state.current_tracks, guild_id, track)

        new_state = %{state |
          queues: new_queues,
          current_tracks: new_current_tracks,
          history: new_history
        }

        {:ok, track, new_state}

      {:empty, _} ->
        {:error, :empty_queue, state}
    end
  end

  defp skip_current_track(state, guild_id) do
    current = Map.get(state.current_tracks, guild_id)

    if current do
      # Добавляем в историю и берем следующий
      new_history = add_to_history(state.history, guild_id, current)

      case get_next_track(%{state | history: new_history}, guild_id) do
        {:ok, next_track, new_state} ->
          {:ok, current, new_state}

        {:error, :empty_queue, new_state} ->
          # Очередь пуста, просто очищаем текущий трек
          new_current_tracks = Map.delete(state.current_tracks, guild_id)
          new_state = %{new_state | current_tracks: new_current_tracks}
          {:ok, current, new_state}
      end
    else
      {:error, "No current track to skip", state}
    end
  end

  defp add_to_history(history, guild_id, track) when track != nil do
    guild_history = Map.get(history, guild_id, :queue.new())
    new_history = :queue.in(track, guild_history)

    # Ограничиваем размер истории
    trimmed_history = trim_history(new_history, 50)
    Map.put(history, guild_id, trimmed_history)
  end

  defp add_to_history(history, _guild_id, _track), do: history

  defp trim_history(queue, max_size) do
    if :queue.len(queue) > max_size do
      {{:value, _}, trimmed} = :queue.out(queue)
      trimmed
    else
      queue
    end
  end
end