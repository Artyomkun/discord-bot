defmodule MusicCore.AudioStream.Processor do
  @moduledoc """
  Процессор аудио потоков для MusicCore.

  Управляет обработкой аудио данных, очередью задач и распределением нагрузки.
  """

  use GenServer
  require Logger

  alias MusicCore.{Metrics, Cache, Buffer}
  alias MusicCore.AudioEffects.Effects
  alias MusicCore.GoProcessor.Client, as: GoClient
  alias MusicCore.JavaGateway.Client, as: JavaClient

  # Статистика для метрик
  @metrics [
    :processing_time,
    :queue_time,
    :effect_time,
    :cache_hit_rate,
    :error_rate
  ]

  # API

  @doc """
  Запустить процессор.
  """
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Остановить процессор.
  """
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Обработать аудио поток.
  """
  def process_audio(stream_id, audio_data, effects \\ []) do
    GenServer.call(__MODULE__, {:process_audio, stream_id, audio_data, effects})
  end

  @doc """
  Обработать аудио асинхронно.
  """
  def process_audio_async(stream_id, audio_data, effects \\ [], callback \\ nil) do
    GenServer.cast(__MODULE__, {:process_audio_async, stream_id, audio_data, effects, callback})
  end

  @doc """
  Остановить обработку потока.
  """
  def stop_stream(stream_id) do
    GenServer.call(__MODULE__, {:stop_stream, stream_id})
  end

  @doc """
  Получить статус потока.
  """
  def stream_status(stream_id) do
    GenServer.call(__MODULE__, {:stream_status, stream_id})
  end

  @doc """
  Получить статистику процессора.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Получить размер очереди.
  """
  def queue_size do
    GenServer.call(__MODULE__, :queue_size)
  end

  @doc """
  Очистить очередь.
  """
  def clear_queue do
    GenServer.call(__MODULE__, :clear_queue)
  end

  @doc """
  Обновить конфигурацию процессора.
  """
  def update_config(opts) do
    GenServer.call(__MODULE__, {:update_config, opts})
  end

  @doc """
  Graceful shutdown процессора.
  """
  def graceful_shutdown(timeout \\ 30_000) do
    GenServer.call(__MODULE__, {:graceful_shutdown, timeout}, timeout + 5_000)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    max_concurrent = Keyword.get(opts, :max_concurrent, 10)
    max_queue_size = Keyword.get(opts, :max_queue_size, 100)
    processing_timeout = Keyword.get(opts, :processing_timeout, 30_000)
    cache_ttl = Keyword.get(opts, :cache_ttl, :timer.minutes(5))

    state = %{
      active_streams: %{},
      queue: :queue.new(),
      max_concurrent: max_concurrent,
      max_queue_size: max_queue_size,
      processing_timeout: processing_timeout,
      cache_ttl: cache_ttl,
      stats: %{
        total_processed: 0,
        total_errors: 0,
        active_count: 0,
        queued_count: 0,
        cache_hits: 0,
        cache_misses: 0,
        processing_time_sum: 0,
        queue_time_sum: 0,
        effect_times: %{}
      },
      config: %{
        use_cache: Keyword.get(opts, :use_cache, true),
        use_go_backend: Keyword.get(opts, :use_go_backend, false),
        use_java_backend: Keyword.get(opts, :use_java_backend, false),
        enable_metrics: Keyword.get(opts, :enable_metrics, true)
      },
      shutdown_timer: nil,
      shutdown_timeout: Keyword.get(opts, :shutdown_timeout, 30_000),
      processing_tasks: %{}
    }

    Logger.info("AudioStreaming.Processor started with max_concurrent: #{max_concurrent}")

    # Запускаем периодическую очистку метрик
    schedule_metrics_cleanup()

    {:ok, state}
  end

  @impl true
  def handle_call({:process_audio, stream_id, audio_data, effects}, from, state) do
    queue_start = System.monotonic_time(:millisecond)
    Metrics.record(:audio_processing_start, 1, %{stream_id: stream_id, effects_count: length(effects)})

    if map_size(state.active_streams) >= state.max_concurrent do
      if :queue.len(state.queue) >= state.max_queue_size do
        Metrics.record(:audio_processing_error, 1, %{stream_id: stream_id, error: :queue_full})
        {:reply, {:error, :queue_full}, state}
      else
        # Добавляем в очередь с метаданными
        task = %{
          type: :process_audio,
          stream_id: stream_id,
          audio_data: audio_data,
          effects: effects,
          from: from,
          queue_start: queue_start
        }
        new_queue = :queue.in(task, state.queue)

        new_stats = update_in(state.stats.queued_count, &(&1 + 1))

        {:reply, {:queued, stream_id}, %{state | queue: new_queue, stats: new_stats}}
      end
    else
      # Запускаем обработку сразу
      start_processing_task(stream_id, audio_data, effects, from, queue_start, state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:stop_stream, stream_id}, _from, state) do
    case Map.get(state.active_streams, stream_id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}

      task_ref ->
        # Отменяем задачу
        Process.demonitor(task_ref, [:flush])
        new_active = Map.delete(state.active_streams, stream_id)

        Metrics.record(:stream_stopped, 1, %{stream_id: stream_id, reason: :manual})

        new_stats = update_in(state.stats.active_count, &max(0, &1 - 1))

        {:reply, :ok, %{state | active_streams: new_active, stats: new_stats}}
    end
  end

  @impl true
  def handle_call({:stream_status, stream_id}, _from, state) do
    status = case Map.get(state.active_streams, stream_id) do
      nil ->
        # Проверяем очередь
        queued = Enum.any?(:queue.to_list(state.queue), fn task ->
          task.stream_id == stream_id
        end)

        if queued do
          :queued
        else
          :unknown
        end

      _ ->
        :processing
    end

    {:reply, status, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    avg_processing_time = if state.stats.total_processed > 0 do
      state.stats.processing_time_sum / state.stats.total_processed
    else
      0
    end

    avg_queue_time = if state.stats.total_processed > 0 do
      state.stats.queue_time_sum / state.stats.total_processed
    else
      0
    end

    cache_hit_rate = if (state.stats.cache_hits + state.stats.cache_misses) > 0 do
      state.stats.cache_hits / (state.stats.cache_hits + state.stats.cache_misses)
    else
      0
    end

    stats = Map.merge(state.stats, %{
      active_streams: map_size(state.active_streams),
      queue_size: :queue.len(state.queue),
      max_concurrent: state.max_concurrent,
      max_queue_size: state.max_queue_size,
      avg_processing_time: avg_processing_time,
      avg_queue_time: avg_queue_time,
      cache_hit_rate: cache_hit_rate,
      uptime: System.monotonic_time(:millisecond) / 1000
    })

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:queue_size, _from, state) do
    {:reply, :queue.len(state.queue), state}
  end

  @impl true
  def handle_call(:clear_queue, _from, state) do
    cleared_count = :queue.len(state.queue)
    new_queue = :queue.new()
    new_stats = update_in(state.stats.queued_count, &(&1 - cleared_count))

    Logger.info("Cleared #{cleared_count} tasks from queue")

    {:reply, cleared_count, %{state | queue: new_queue, stats: new_stats}}
  end

  @impl true
  def handle_call({:update_config, opts}, _from, state) do
    new_config = Map.merge(state.config, opts)

    max_concurrent = Keyword.get(opts, :max_concurrent, state.max_concurrent)
    max_queue_size = Keyword.get(opts, :max_queue_size, state.max_queue_size)

    # Обновляем лимиты
    new_state = %{state |
      config: new_config,
      max_concurrent: max_concurrent,
      max_queue_size: max_queue_size
    }

    Logger.info("Processor config updated: #{inspect(opts)}")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:graceful_shutdown, timeout}, _from, state) do
    Logger.info("Starting graceful shutdown of AudioStreaming.Processor")

    timer = Process.send_after(self(), :shutdown_timeout, timeout)

    # Останавливаем приём новых задач
    active_count = map_size(state.active_streams)
    queued_count = :queue.len(state.queue)

    Logger.info("Active streams: #{active_count}, Queued tasks: #{queued_count}")

    new_state = %{state | shutdown_timer: timer}

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:process_audio_async, stream_id, audio_data, effects, callback}, state) do
    queue_start = System.monotonic_time(:millisecond)
    Metrics.record(:audio_processing_start, 1, %{stream_id: stream_id, effects_count: length(effects), async: true})

    if map_size(state.active_streams) >= state.max_concurrent do
      if :queue.len(state.queue) >= state.max_queue_size do
        Metrics.record(:audio_processing_error, 1, %{stream_id: stream_id, error: :queue_full, async: true})

        if callback, do: callback.({:error, :queue_full})
      else
        task = %{
          type: :process_audio_async,
          stream_id: stream_id,
          audio_data: audio_data,
          effects: effects,
          callback: callback,
          queue_start: queue_start
        }
        new_queue = :queue.in(task, state.queue)
        new_stats = update_in(state.stats.queued_count, &(&1 + 1))

        {:noreply, %{state | queue: new_queue, stats: new_stats}}
      end
    else
      start_async_processing_task(stream_id, audio_data, effects, callback, queue_start, state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:processing_complete, stream_id, result, from, processing_time}, state) do
    task_ref = Map.get(state.active_streams, stream_id)

    if task_ref do
      Process.demonitor(task_ref, [:flush])
    end

    new_active = Map.delete(state.active_streams, stream_id)

    new_stats = state.stats
    |> update_in([:active_count], &max(0, &1 - 1))
    |> update_in([:total_processed], &(&1 + 1))
    |> update_in([:processing_time_sum], &(&1 + processing_time))

    # Отвечаем синхронному клиенту
    if from do
      GenServer.reply(from, {:ok, result})
    end

    # Отправляем метрики
    Metrics.record(:audio_processing_stop, 1, %{stream_id: stream_id, status: :success, duration_ms: processing_time})

    # Обрабатываем очередь
    new_state = %{state | active_streams: new_active, stats: new_stats}

    # Проверяем очередь
    if not :queue.is_empty(new_state.queue) do
      schedule_queue_processing()
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:processing_failed, stream_id, error, from, processing_time}, state) do
    task_ref = Map.get(state.active_streams, stream_id)

    if task_ref do
      Process.demonitor(task_ref, [:flush])
    end

    new_active = Map.delete(state.active_streams, stream_id)

    new_stats = state.stats
    |> update_in([:active_count], &max(0, &1 - 1))
    |> update_in([:total_errors], &(&1 + 1))

    # Отвечаем синхронному клиенту
    if from do
      GenServer.reply(from, {:error, error})
    end

    Metrics.record(:audio_processing_error, 1, %{stream_id: stream_id, error: inspect(error)})

    new_state = %{state | active_streams: new_active, stats: new_stats}

    # Проверяем очередь
    if not :queue.is_empty(new_state.queue) do
      schedule_queue_processing()
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:process_queue, ref}, state) do
    # Проверяем, не устарела ли задача
    if ref == state.shutdown_timer do
      # Пропускаем обработку очереди при shutdown
      {:noreply, state}
    else
      {new_queue, new_state} = process_queue(state)
      {:noreply, %{new_state | queue: new_queue}}
    end
  end

  @impl true
  def handle_info(:shutdown_timeout, state) do
    Logger.warning("Graceful shutdown timeout reached, forcing shutdown")

    # Принудительно останавливаем все активные задачи
    for {stream_id, task_ref} <- state.active_streams do
      Process.demonitor(task_ref, [:flush])
      Logger.warning("Forcing stop of stream #{stream_id}")
    end

    # Очищаем очередь
    cleared_count = :queue.len(state.queue)
    if cleared_count > 0 do
      Logger.warning("Clearing #{cleared_count} queued tasks")
    end

    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Находим задачу по монитору
    case Enum.find(state.active_streams, fn {_stream_id, task_ref} -> task_ref == ref end) do
      {stream_id, _task_ref} ->
        Logger.error("Processing task died for stream #{stream_id}: #{inspect(reason)}")

        new_active = Map.delete(state.active_streams, stream_id)
        new_stats = update_in(state.stats.total_errors, &(&1 + 1))

        Metrics.record(:audio_processing_error, 1, %{stream_id: stream_id, error: :process_died})

        {:noreply, %{state | active_streams: new_active, stats: new_stats}}

      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:cleanup_metrics, state) do
    # Очистка старых метрик из кэша
    schedule_metrics_cleanup()
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("AudioStreaming.Processor terminating: #{inspect(reason)}")

    # Останавливаем все активные задачи
    for {stream_id, task_ref} <- state.active_streams do
      Process.demonitor(task_ref, [:flush])
      Logger.info("Terminating stream #{stream_id}")
    end

    # Сохраняем финальную статистику
    if state.config.enable_metrics do
      Metrics.record(:processor_shutdown, 1, %{
        reason: inspect(reason),
        total_processed: state.stats.total_processed,
        total_errors: state.stats.total_errors
      })
    end

    :ok
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp start_processing_task(stream_id, audio_data, effects, from, queue_start, state) do
    processing_start = System.monotonic_time(:millisecond)

    # Проверяем кэш
    cached = if state.config.use_cache do
      case get_cached_result(stream_id, audio_data, effects) do
        {:ok, cached_data} ->
          stats = update_in(state.stats.cache_hits, &(&1 + 1))
          true
          cached_data
        _ ->
          stats = update_in(state.stats.cache_misses, &(&1 + 1))
          nil
      end
    else
      nil
    end

    if cached do
      # Отправляем кэшированный результат
      processing_time = System.monotonic_time(:millisecond) - processing_start
      queue_time = processing_start - queue_start

      state = update_stats_with_queue_time(state, queue_time)

      send(self(), {:processing_complete, stream_id, cached, from, processing_time})
    else
      # Запускаем асинхронную задачу
      parent = self()

      task_ref = spawn_link(fn ->
        result = do_process_audio(stream_id, audio_data, effects, state.config)

        processing_time = System.monotonic_time(:millisecond) - processing_start
        queue_time = processing_start - queue_start

        # Отправляем результат обратно
        case result do
          {:ok, processed_data} ->
            # Кэшируем результат
            if state.config.use_cache do
              cache_result(stream_id, audio_data, effects, processed_data, state.cache_ttl)
            end

            send(parent, {:processing_complete, stream_id, processed_data, from, processing_time})

          {:error, error} ->
            send(parent, {:processing_failed, stream_id, error, from, processing_time})
        end
      end)

      # Мониторим задачу
      Process.monitor(task_ref)

      new_active = Map.put(state.active_streams, stream_id, task_ref)
      new_stats = update_in(state.stats.active_count, &(&1 + 1))

      # Обновляем состояние
      Process.put(:processing_time, processing_start)
      Process.put(:queue_time, queue_start)
    end
  end

  defp start_async_processing_task(stream_id, audio_data, effects, callback, queue_start, state) do
    process_start = System.monotonic_time(:millisecond)

    parent = self()

    task_ref = spawn_link(fn ->
      result = do_process_audio(stream_id, audio_data, effects, state.config)

      processing_time = System.monotonic_time(:millisecond) - process_start
      queue_time = process_start - queue_start

      case result do
        {:ok, processed_data} ->
          if state.config.use_cache do
            cache_result(stream_id, audio_data, effects, processed_data, state.cache_ttl)
          end

          if callback, do: callback.({:ok, processed_data})

          send(parent, {:processing_complete, stream_id, processed_data, nil, processing_time})

        {:error, error} ->
          if callback, do: callback.({:error, error})

          send(parent, {:processing_failed, stream_id, error, nil, processing_time})
      end
    end)

    Process.monitor(task_ref)
    start_time = System.monotonic_time()
    queue_time = System.monotonic_time() - start_time
    new_active = Map.put(state.active_streams, stream_id, task_ref)
    new_stats = state.stats
    |> update_in([:active_count], &(&1 + 1))
    |> update_queue_stats(queue_time)

    # Обновляем состояние процессора
    Process.put(:processing_time, process_start)
  end

  defp update_queue_stats(state, queue_time) do
    stats = Map.get(state, :stats, %{})
    queue_times = Map.get(stats, :queue_times, [])
    updated_queue_times = [queue_time | queue_times] |> Enum.take(100)
    avg_queue_time = if updated_queue_times == [], do: 0, else: Enum.sum(updated_queue_times) / length(updated_queue_times)

    updated_stats = %{stats | queue_times: updated_queue_times, avg_queue_time: avg_queue_time}
    %{state | stats: updated_stats}
  end

  defp do_process_audio(stream_id, audio_data, effects, config) do
    try do
      # Выбираем бэкенд для обработки
      processed_data = cond do
        config.use_go_backend ->
          process_with_go(stream_id, audio_data, effects)

        config.use_java_backend ->
          process_with_java(stream_id, audio_data, effects)

        true ->
          process_locally(stream_id, audio_data, effects)
      end

      {:ok, processed_data}
    rescue
      error ->
        Logger.error("Error processing audio for stream #{stream_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp process_locally(stream_id, audio_data, effects) do
    # Локальная обработка через Effects модуль
    Effects.apply_effects(audio_data, effects, [stream_id: stream_id])
  end

  defp process_with_go(stream_id, audio_data, effects) do
    # Обработка через Go сервис
    case GoClient.process_audio(stream_id, audio_data, effects) do
      {:ok, result} -> result
      {:error, _} -> process_locally(stream_id, audio_data, effects)  # fallback
    end
  end

  defp process_with_java(stream_id, audio_data, effects) do
    # Обработка через Java Gateway
    case JavaClient.process_audio(stream_id, audio_data, effects) do
      {:ok, result} -> result
      {:error, _} -> process_locally(stream_id, audio_data, effects)  # fallback
    end
  end

  defp process_queue(state) do
    if map_size(state.active_streams) < state.max_concurrent and not :queue.is_empty(state.queue) do
      {{:value, task}, new_queue} = :queue.out(state.queue)

      queue_time = System.monotonic_time(:millisecond) - task.queue_start

      case task.type do
        :process_audio ->
          start_processing_task(task.stream_id, task.audio_data, task.effects, task.from, task.queue_start, state)

        :process_audio_async ->
          start_async_processing_task(task.stream_id, task.audio_data, task.effects, task.callback, task.queue_start, state)
      end

      new_stats = update_in(state.stats.queued_count, &max(0, &1 - 1))

      # Рекурсивно обрабатываем очередь (через schedule, чтобы не блокировать)
      if not :queue.is_empty(new_queue) do
        schedule_queue_processing()
      end

      {new_queue, %{state | queue: new_queue, stats: new_stats}}
    else
      {state.queue, state}
    end
  end

  defp get_cached_result(stream_id, audio_data, effects) do
    cache_key = generate_cache_key(audio_data, effects)
    Cache.get(:audio_cache, cache_key)
  end

  defp cache_result(stream_id, audio_data, effects, result, ttl) do
    cache_key = generate_cache_key(audio_data, effects)
    Cache.put(:audio_cache, cache_key, result, ttl)
  end

  defp generate_cache_key(audio_data, effects) do
    audio_hash = :crypto.hash(:sha256, audio_data) |> Base.encode16(case: :lower)
    effects_hash = :crypto.hash(:sha256, Jason.encode!(effects)) |> Base.encode16(case: :lower)
    "audio_processing:#{audio_hash}:#{effects_hash}"
  end

  defp update_stats_with_queue_time(state, queue_time) do
    update_in(state.stats.queue_time_sum, &(&1 + queue_time))
  end

  defp schedule_queue_processing do
    Process.send_after(self(), {:process_queue, make_ref()}, 10)
  end

  defp schedule_metrics_cleanup do
    Process.send_after(self(), :cleanup_metrics, :timer.minutes(5))
  end
end
