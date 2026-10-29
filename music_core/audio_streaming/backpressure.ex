defmodule MusicCore.AudioStreaming.Backpressure do
  @moduledoc """
  Управление обратным давлением (backpressure) для аудио-потоков.
  Следит за нагрузкой на систему и решает, можно ли принимать новые задачи.
  """

  use GenServer
  require Logger
  import MusicCore.Telemetry.Metrics

  # Клиентский API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Проверить, можно ли принять задачу с заданным приоритетом
  """
  def should_accept?(priority \\ :normal) do
    GenServer.call(__MODULE__, {:should_accept?, priority})
  end

  @doc """
  Получить текущее состояние backpressure
  """
  def current_state do
    GenServer.call(__MODULE__, :current_state)
  end

  @doc """
  Увеличить лимит параллельных задач
  """
  def increase_capacity(factor \\ 0.1) do
    GenServer.cast(__MODULE__, {:adjust_capacity, factor})
  end

  @doc """
  Уменьшить лимит параллельных задач
  """
  def decrease_capacity(factor \\ 0.1) do
    GenServer.cast(__MODULE__, {:adjust_capacity, -factor})
  end

  @doc """
  Обновить лимит параллельных задач
  """
  def update_concurrent_limit(new_limit) do
    GenServer.cast(__MODULE__, {:set_concurrent_limit, new_limit})
  end

  @doc """
  Проверить, можно ли принять больше задач
  """
  def can_accept_more? do
    GenServer.call(__MODULE__, :can_accept_more?)
  end

  def init(opts) do
    state = %{
      limits: %{
        high: %{
          concurrent: 5,
          queue: 100,
          current: 0
        },
        normal: %{
          concurrent: 10,
          queue: 500,
          current: 0
        },
        low: %{
          concurrent: 3,
          queue: 200,
          current: 0
        }
      },
      global: %{
        max_concurrent: 20,
        current_concurrent: 0,
        max_queue: 1000,
        current_queue: 0
      },
      metrics: %{
        cpu_load: 0.0,
        memory_usage: 0.0,
        avg_response_time: 0,
        error_rate: 0.0
      },
      adaptation: %{
        min_concurrent: 5,
        max_concurrent: 50,
        scale_up_threshold: 0.7,
        scale_down_threshold: 0.3,
        last_scale: System.system_time(:millisecond)
      },
      history: %{
        cpu: :queue.new(),
        memory: :queue.new(),
        response_time: :queue.new()
      }
    }

    attach_telemetry()
    schedule_metrics_collection()
    schedule_adaptation()

    {:ok, state}
  end

  def handle_call({:should_accept?, priority}, state) do
    priority = normalize_priority(priority)
    limit = get_in(state, [:limits, priority, :concurrent])
    current = get_in(state, [:limits, priority, :current])
    global_current = state.global.current_concurrent
    global_max = state.global.max_concurrent

    can_accept =
      current < limit &&
      global_current < global_max &&
      system_healthy?(state)

    new_state = if can_accept do
      state
      |> put_in([:limits, priority, :current], current + 1)
      |> put_in([:global, :current_concurrent], global_current + 1)
    else
      state
    end

    {:reply, can_accept, new_state}
  end

  def handle_call(:can_accept_more?, state) do
    result =
      state.global.current_concurrent < state.global.max_concurrent &&
      system_healthy?(state)

    {:reply, result, state}
  end

  def handle_call(:current_state, state) do
    current = %{
      limits: state.limits,
      global: state.global,
      metrics: state.metrics,
      adaptation: state.adaptation,
      healthy: system_healthy?(state),
      utilization: calculate_utilization(state)
    }

    {:reply, current, state}
  end

  def handle_cast({:adjust_capacity, factor}, state) do
    new_limit = max(
      state.adaptation.min_concurrent,
      min(
        state.adaptation.max_concurrent,
        round(state.global.max_concurrent * (1 + factor))
      )
    )

    new_state = %{state |
      global: %{state.global | max_concurrent: new_limit},
      adaptation: %{state.adaptation | last_scale: System.system_time(:millisecond)}
    }

    Logger.info("Adjusted concurrent limit to #{new_limit} (factor: #{factor})")
    {:noreply, new_state}
  end

  def handle_cast({:set_concurrent_limit, new_limit}, state) do
    new_limit = max(
      state.adaptation.min_concurrent,
      min(state.adaptation.max_concurrent, new_limit)
    )

    new_state = %{state |
      global: %{state.global | max_concurrent: new_limit}
    }

    Logger.info("Set concurrent limit to #{new_limit}")
    {:noreply, new_state}
  end

  def handle_cast({:task_completed, priority}, state) do
    priority = normalize_priority(priority)

    current = get_in(state, [:limits, priority, :current])
    global_current = state.global.current_concurrent

    new_state = state
      |> put_in([:limits, priority, :current], max(0, current - 1))
      |> put_in([:global, :current_concurrent], max(0, global_current - 1))

    {:noreply, new_state}
  end

  def handle_cast(metrics, state) do
    new_state = Metrics.update(state, metrics)
    {:noreply, new_state}
  end

  def handle_info(:collect_metrics, state) do
    new_state = collect_system_metrics(state)
    schedule_metrics_collection()
    {:noreply, new_state}
  end

  def handle_info(:adapt, state) do
    new_state = perform_adaptation(state)
    schedule_adaptation()
    {:noreply, new_state}
  end

  defp schedule_metrics_collection do
    Process.send_after(self(), :collect_metrics, 5000)
  end

  defp schedule_adaptation do
    Process.send_after(self(), :adapt, 10000)
  end

  defp normalize_priority(priority) when is_atom(priority), do: priority
  defp normalize_priority(_), do: :normal

  defp system_healthy?(state) do
    state.metrics.cpu_load < 0.8 &&
    state.metrics.memory_usage < 0.8 &&
    state.metrics.error_rate < 0.1
  end

  defp calculate_utilization(state) do
    %{
      global: state.global.current_concurrent / state.global.max_concurrent,
      high: get_in(state, [:limits, :high, :current]) / get_in(state, [:limits, :high, :concurrent]),
      normal: get_in(state, [:limits, :normal, :current]) / get_in(state, [:limits, :normal, :concurrent]),
      low: get_in(state, [:limits, :low, :current]) / get_in(state, [:limits, :low, :concurrent])
    }
  end

  defp collect_system_metrics(state) do
    cpu_load = get_cpu_load()
    memory_usage = get_memory_usage()
    {avg_response, error_rate} = get_performance_metrics()

    history = state.history
    history = update_history(history, :cpu, cpu_load)
    history = update_history(history, :memory, memory_usage)
    history = update_history(history, :response_time, avg_response)

    %{state |
      metrics: %{
        cpu_load: cpu_load,
        memory_usage: memory_usage,
        avg_response_time: avg_response,
        error_rate: error_rate
      },
      history: history
    }
  end

  @doc """
  Получить загрузку CPU (0.0 - 1.0)
  """
  defp get_cpu_load do
    get_cpu_load_os_mon()
    |> fallback_to(&get_cpu_load_system_monitor/0)
    |> fallback_to(&get_cpu_load_avg1/0)
    |> fallback_to(&get_cpu_load_fallback/0)
  end

  defp fallback_to(nil, func), do: func.()
  defp fallback_to(value), do: value

  defp get_cpu_load_os_mon do
    try do
      case :cpu_sup.avg1() do
        {:error, _} -> nil
        loads when is_list(loads) ->
          total = Enum.reduce(loads, 0, fn load, acc -> acc + load end)
          total / length(loads)
        load when is_number(load) ->
          load
      end
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end

  defp get_cpu_load_system_monitor do
    try do
      case :erlang.system_info(:cpu_topology) do
        :unknown -> nil
        topology ->
          total = :erlang.system_info(:schedulers_online)
          util = :erlang.statistics(:scheduler_wall_time)

          if is_list(util) and length(util) > 0 do
            avg = Enum.reduce(util, 0, fn {active, total}, acc ->
              acc + (active / total)
            end) / length(util)
            avg
          else
            nil
          end
      end
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end

  defp get_cpu_load_avg1 do
    try do
      case :cpu_sup.avg1() do
        load when is_number(load) -> load / 100
        _ -> nil
      end
    rescue
      _ -> nil
    catch
      _, _ -> nil
    end
  end

  defp get_cpu_load_fallback do
    process_count = :erlang.system_info(:process_count)
    run_queue = :erlang.statistics(:run_queue)

    load = 0.1 + (run_queue / 100) + (process_count / 10000)
    min(load, 1.0)
  end

  defp get_memory_usage do
    case :memsup.get_system_memory_data() do
      {:ok, data} ->
        total = data[:total_memory]
        free = data[:free_memory]
        1 - free / total
      _ -> 0.0
    end
  end

  defp attach_telemetry do
    :telemetry.detach("backpressure-metrics")

    :telemetry.attach_many(
      "backpressure-metrics",
      [
        [:music_core, :processor, :task_completed],
        [:music_core, :processor, :task_failed]
      ],
      &handle_telemetry/3,
      nil
    )
  end

  defp handle_telemetry([:music_core, :processor, :task_completed], measurements, metadata) do
    update_performance_metrics(measurements.processing_time, true)
  end

  defp handle_telemetry([:music_core, :processor, :task_failed]) do
    update_performance_metrics(0, false)
  end

  defp get_current_metrics do
    case :global.whereis_name(:performance_metrics) do
      :undefined -> {0.1, 0.01}
      pid ->
        :erlang.trace(pid, true, [:receive])
        {avg, err} = :erlang.call(pid, {:get_metrics})
        :erlang.trace(pid, false, [:receive])
        {avg, err}
    end
  end

  defp update_history(history, key, value) do
    queue = Map.get(history, key, :queue.new())
    new_queue = :queue.in(value, queue)

    trimmed_queue = if :queue.len(new_queue) > 100 do
      {{:value, _}, q} = :queue.out(new_queue)
      q
    else
      new_queue
    end

    Map.put(history, key, trimmed_queue)
  end

  defp perform_adaptation(state) do
    utilization = calculate_utilization(state)
    global_util = utilization.global

    cond do
      global_util > state.adaptation.scale_up_threshold &&
      state.global.max_concurrent < state.adaptation.max_concurrent ->
        Logger.warning("High load (#{Float.round(global_util, 2)}), scaling up")
        increase_capacity(0.1)
        state

      global_util < state.adaptation.scale_down_threshold &&
      state.global.max_concurrent > state.adaptation.min_concurrent ->
        Logger.info("Low load (#{Float.round(global_util, 2)}), scaling down")
        decrease_capacity(0.1)
        state

      true ->
        state
    end
  end

  defp get_performance_metrics do
    case :global.whereis_name(:performance_metrics) do
      :undefined -> {10, 0.01}
      pid ->
        try do
          {avg_response, error_rate} = :erlang.call(pid, :get_metrics)
          {avg_response, error_rate}
        rescue
          _ -> {10, 0.01}
        end
    end
  end

  defp update_performance_metrics(processing_time, success) do
    case :persistent_term.get({:performance_metrics, :last}, nil) do
      nil ->
        :persistent_term.put({:performance_metrics, :last}, %{
          avg_response: processing_time,
          error_rate: if(success, do: 0, else: 1)
        })
      metrics ->
        alpha = 0.1
        new_avg = metrics.avg_response * (1 - alpha) + processing_time * alpha
        new_error_rate = metrics.error_rate * (1 - alpha) + (if(success, do: 0, else: 1)) * alpha
        :persistent_term.put({:performance_metrics, :last}, %{
          avg_response: new_avg,
          error_rate: new_error_rate
        })
    end
  end
end
