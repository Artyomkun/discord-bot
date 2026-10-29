defmodule MusicCore.AudioStream.Manager do
  @moduledoc """
  Менеджер аудио стримов для MusicCore.

  Управляет жизненным циклом аудио потоков, их регистрацией и мониторингом.
  """

  use GenServer
  require Logger

  alias MusicCore.{Metrics, Cache, AudioStreaming.Processor}

  # API

  @doc """
  Запустить менеджер стримов.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Зарегистрировать новый аудио поток.
  """
  def register_stream(stream_id, guild_id, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register_stream, stream_id, guild_id, metadata})
  end

  @doc """
  Получает поток по ID.
  """
  @spec get_stream(String.t()) :: map() | nil
  def get_stream(stream_id) do
    GenServer.call(__MODULE__, {:get_stream, stream_id})
  end

  @doc """
  Обновляет существующий поток (полная замена).
  """
  @spec update_stream(map()) :: :ok | {:error, term()}
  def update_stream(stream) do
    GenServer.call(__MODULE__, {:update_stream, stream})
  end

  @doc """
  Отменить регистрацию потока.
  """
  def unregister_stream(stream_id) do
    GenServer.call(__MODULE__, {:unregister_stream, stream_id})
  end

  @doc """
  Получить информацию о потоке.
  """
  def get_stream_info(stream_id) do
    GenServer.call(__MODULE__, {:get_stream_info, stream_id})
  end

  @doc """
  Получить все активные стримы для гильдии.
  """
  def get_guild_streams(guild_id) do
    GenServer.call(__MODULE__, {:get_guild_streams, guild_id})
  end

  @doc """
  Получить количество активных стримов.
  """
  def active_streams_count do
    GenServer.call(__MODULE__, :active_streams_count)
  end

  @doc """
  Получить статистику по всем стримам.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Остановить все стримы для гильдии.
  """
  def stop_guild_streams(guild_id) do
    GenServer.call(__MODULE__, {:stop_guild_streams, guild_id})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      streams: %{},
      guild_streams: %{},
      stats: %{
        total_registered: 0,
        total_unregistered: 0,
        current_active: 0,
        max_concurrent: 0,
        errors: 0
      }
    }

    Process.send_after(self(), :cleanup_expired, :timer.minutes(5))

    Logger.info("AudioStream.Manager started")

    {:ok, state}
  end

  @impl true
  def handle_call({:get_stream, stream_id}, state) do
    {:reply, Map.get(state.streams, stream_id), state}
  end

  @impl true
  def handle_call({:update_stream, stream}, state) do
    case Map.has_key?(state.streams, stream.id) do
      true ->
        new_streams = Map.put(state.streams, stream.id, stream)
        {:reply, :ok, %{state | streams: new_streams}}

      false ->
        {:reply, {:error, :stream_not_found}, state}
    end
  end

  @impl true
  def handle_call({:register_stream, stream_id, guild_id, metadata}, state) do
    if Map.has_key?(state.streams, stream_id) do
      {:reply, {:error, :already_registered}, state}
    else
      stream_info = %{
        stream_id: stream_id,
        guild_id: guild_id,
        started_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now(),
        metadata: metadata,
        status: :active
      }

      new_streams = Map.put(state.streams, stream_id, stream_info)
      guild_list = Map.get(state.guild_streams, guild_id, [])
      new_guild_streams = Map.put(state.guild_streams, guild_id, [stream_id | guild_list])

      new_stats = state.stats
                 |> update_in([:total_registered], &(&1 + 1))
                 |> update_in([:current_active], &(&1 + 1))
                 |> update_in([:max_concurrent], &max(&1, &1 + 1))

      Metrics.stream_started(stream_id, guild_id, metadata)

      Logger.info("Registered stream #{stream_id} for guild #{guild_id}")

      {:reply, {:ok, stream_info}, %{state |
        streams: new_streams,
        guild_streams: new_guild_streams,
        stats: new_stats
      }}
    end
  end

  @impl true
  def handle_call({:unregister_stream, stream_id}, state) do
    case Map.pop(state.streams, stream_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, state}

      {stream_info, new_streams} ->
        guild_id = stream_info.guild_id
        guild_list = Map.get(state.guild_streams, guild_id, [])
        new_guild_list = List.delete(guild_list, stream_id)
        new_guild_streams = if new_guild_list == [], do: Map.delete(state.guild_streams, guild_id),
                                                   else: Map.put(state.guild_streams, guild_id, new_guild_list)

        duration = DateTime.diff(DateTime.utc_now(), stream_info.started_at, :second)
        new_stats = state.stats
                   |> update_in([:total_unregistered], &(&1 + 1))
                   |> update_in([:current_active], &max(0, &1 - 1))

        Metrics.stream_stopped(stream_id, guild_id, duration, %{reason: :unregistered})

        Logger.info("Unregistered stream #{stream_id} for guild #{guild_id}")

        {:reply, :ok, %{state |
          streams: new_streams,
          guild_streams: new_guild_streams,
          stats: new_stats
        }}
    end
  end

  @impl true
  def handle_call({:get_stream_info, stream_id}, state) do
    case Map.get(state.streams, stream_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      stream_info ->
        updated_info = Map.put(stream_info, :last_activity, DateTime.utc_now())
        new_streams = Map.put(state.streams, stream_id, updated_info)

        {:reply, {:ok, updated_info}, %{state | streams: new_streams}}
    end
  end

  @impl true
  def handle_call({:get_guild_streams, guild_id}, state) do
    stream_ids = Map.get(state.guild_streams, guild_id, [])
    streams = Enum.map(stream_ids, fn id -> Map.get(state.streams, id) end) |> Enum.reject(&is_nil/1)

    {:reply, streams, state}
  end

  @impl true
  def handle_call(:active_streams_count, state) do
    {:reply, map_size(state.streams), state}
  end

  @impl true
  def handle_call(:get_stats, state) do
    stats = Map.merge(state.stats, %{
      guilds_with_streams: map_size(state.guild_streams),
      streams_per_guild: calculate_streams_per_guild(state.guild_streams)
    })

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:stop_guild_streams, guild_id}, state) do
    stream_ids = Map.get(state.guild_streams, guild_id, [])

    Enum.each(stream_ids, fn stream_id ->
      Processor.stop_stream(stream_id)

      # Отменяем регистрацию
      unregister_stream(stream_id)
    end)

    Logger.info("Stopped all streams for guild #{guild_id}")

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = DateTime.utc_now()
    expired_timeout = :timer.minutes(30)

    {expired_streams, active_streams} = Enum.split_with(state.streams, fn {id, info} ->
      DateTime.diff(now, info.last_activity, :millisecond) > expired_timeout
    end)

    if length(expired_streams) > 0 do
      Logger.info("Cleaning up #{length(expired_streams)} expired streams")

      # Удаляем истекшие стримы
      expired_ids = Enum.map(expired_streams, fn {id, _} -> id end)

      new_guild_streams = remove_from_guild_index(state.guild_streams, expired_ids)

      new_stats = state.stats
                 |> update_in([:current_active], &max(0, &1 - length(expired_streams)))
                 |> update_in([:errors], &(&1 + length(expired_streams)))

      Enum.each(expired_ids, fn stream_id ->
        Metrics.record(:stream_expired, 1, %{stream_id: stream_id})
      end)

      # Запускаем следующую очистку
      Process.send_after(self(), :cleanup_expired, :timer.minutes(5))

      {:noreply, %{state |
        streams: Map.new(active_streams),
        guild_streams: new_guild_streams,
        stats: new_stats
      }}
    else
      # Запускаем следующую очистку
      Process.send_after(self(), :cleanup_expired, :timer.minutes(5))

      {:noreply, state}
    end
  end

  # Приватные функции

  defp calculate_streams_per_guild(guild_streams) do
    Enum.map(guild_streams, fn {guild_id, streams} ->
      {guild_id, length(streams)}
    end)
    |> Enum.into(%{})
  end

  defp remove_from_guild_index(guild_streams, stream_ids) do
    Enum.reduce(guild_streams, %{}, fn {guild_id, streams}, acc ->
      new_streams = Enum.reject(streams, &(&1 in stream_ids))

      if new_streams == [] do
        acc
      else
        Map.put(acc, guild_id, new_streams)
      end
    end)
  end
end
