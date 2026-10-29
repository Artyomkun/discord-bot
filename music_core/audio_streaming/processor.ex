defmodule MusicCore.AudioStreaming.Processor do
  use GenServer, restart: :transient

  require Logger

  alias MusicCore.{
    Audioffects.Effects.Effects,
    Metrics,
    Cache,
    CircuitBreaker,
    ServiceRegistry
  }

  alias MusicCore.AudioStreaming.{
    DiscordClient,
    Backpressure,
    QualityManager,
    TaskSupervisor
  }

  # API
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Начать потоковое воспроизведение по URL
  """
  def start_stream(url, user_id, guild_id, options \\ []) do
    stream_id = generate_stream_id(user_id, guild_id)

    Task.Supervisor.start_child(TaskSupervisor, fn ->
      case fetch_and_process_stream(url, user_id, guild_id, options) do
        {:ok, result} ->
          Metrics.record(:stream_started, 1, %{stream_id: stream_id, guild_id: guild_id})
          broadcast({:stream_ready, stream_id, result})
        {:error, reason} ->
          Metrics.record(:stream_failed, 1, %{stream_id: stream_id, error: reason})
          broadcast({:stream_failed, stream_id, reason})
      end
    end)

    {:ok, stream_id}
  end

  @doc """
  Асинхронная обработка аудио
  """
  def process_audio(audio_data, user_id, guild_id, opts \\ []) do
    priority = opts[:priority] || :normal
    quality = opts[:quality] || :balanced

    job_id = generate_job_id(user_id, guild_id)

    case Backpressure.should_accept?(priority) do
      true ->
        case CircuitBreaker.allow?(:audio_processor) do
          true ->
            Task.Supervisor.start_child(TaskSupervisor, fn ->
              process_job(job_id, audio_data, user_id, guild_id, priority, quality, opts)
            end)
            {:ok, job_id}

          false ->
            {:error, :circuit_open}
        end

      false ->
        {:error, :backpressure}
    end
  end

  @doc """
  Получить статистику
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server

  def init(_opts) do
    state = %{
      started_at: System.monotonic_time(:millisecond),
      total_processed: 0,
      total_errors: 0,
      processing_times: []
    }

    schedule_stats_report()

    {:ok, state}
  end

  def handle_call(:stats, _from, state) do
    uptime = System.monotonic_time(:millisecond) - state.started_at
    avg_time = if state.total_processed > 0 do
      Enum.sum(state.processing_times) / state.total_processed
    else
      0
    end

    stats = %{
      uptime_ms: uptime,
      total_processed: state.total_processed,
      total_errors: state.total_errors,
      avg_processing_time_ms: avg_time,
      error_rate: if(state.total_processed > 0, do: state.total_errors / state.total_processed, else: 0)
    }

    {:reply, stats, state}
  end

  def handle_info(:report_stats, state) do
    stats = %{
      uptime: System.monotonic_time(:millisecond) - state.started_at,
      processed: state.total_processed,
      errors: state.total_errors,
      memory: :erlang.memory(:total),
      processes: :erlang.system_info(:process_count)
    }

    :telemetry.execute([:music_core, :processor, :stats], stats, %{})

    schedule_stats_report()
    {:noreply, state}
  end

  # Private

  defp fetch_and_process_stream(url, user_id, guild_id, options) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, audio_data} <- download_audio(url, options),
         {:ok, processed} <- apply_effects(audio_data, options[:effects] || []),
         :ok <- send_to_discord(guild_id, processed, options) do

      duration = System.monotonic_time(:millisecond) - start_time

      {:ok, %{
        stream_id: generate_stream_id(user_id, guild_id),
        duration_ms: duration,
        size: byte_size(processed),
        effects: options[:effects] || []
      }}
    end
  end

  defp download_audio(url, _options) do
    # Реальная загрузка через Req с таймаутами и ретраями
    case Req.get(url, timeout: 30_000, retry: :transient, retry_delay: 1000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_effects(audio_data, effects) when is_list(effects) do
    case Effects.apply_effects(audio_data, effects, []) do
      {:ok, result} ->
        {:ok, result.audio}
      error ->
        error
    end
  end
  defp apply_effects(audio_data, _), do: {:ok, audio_data}

  defp send_to_discord(guild_id, audio_data, _options) do
    DiscordClient.send_audio(guild_id, audio_data)
  end

  defp process_job(job_id, audio_data, user_id, guild_id, priority, quality, opts) do
    start_time = System.monotonic_time(:millisecond)

    result = case apply_effects(audio_data, opts[:effects] || []) do
      {:ok, processed} ->
        duration = System.monotonic_time(:millisecond) - start_time

        Metrics.record(:job_completed, 1, %{
          job_id: job_id,
          duration_ms: duration,
          priority: priority,
          quality: quality,
          size: byte_size(processed)
        })

        update_stats(job_id, duration, true)

        DiscordClient.send_audio(guild_id, processed)

        {:ok, job_id}

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time

        Metrics.record(:job_failed, 1, %{
          job_id: job_id,
          duration_ms: duration,
          priority: priority,
          quality: quality,
          error: inspect(reason)
        })

        update_stats(job_id, duration, false)

        {:error, reason}
    end

    broadcast({:job_completed, job_id, result})
    result
  end

  defp update_stats(_job_id, duration, success) do
    GenServer.cast(__MODULE__, {:update_stats, duration, success})
  end

  def handle_cast({:update_stats, duration, success}, state) do
    new_processing_times = [duration | state.processing_times] |> Enum.take(100)

    new_state = %{state |
      total_processed: state.total_processed + (if success, do: 1, else: 0),
      total_errors: state.total_errors + (if success, do: 0, else: 1),
      processing_times: new_processing_times
    }

    {:noreply, new_state}
  end

  defp generate_stream_id(user_id, guild_id) do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "stream_#{timestamp}_#{user_id}_#{guild_id}_#{random}"
  end

  defp generate_job_id(user_id, guild_id) do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "job_#{timestamp}_#{user_id}_#{guild_id}_#{random}"
  end

  defp schedule_stats_report do
    Process.send_after(self(), :report_stats, 60_000)
  end

  defp broadcast(message) do
    if Code.ensure_loaded?(Phoenix.PubSub) do
      Phoenix.PubSub.broadcast(MusicCore.PubSub, "audio_processor", message)
    end
  end
end
