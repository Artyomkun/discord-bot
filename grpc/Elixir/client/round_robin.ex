defmodule ElixirClient.Client.RoundRobin do
  @moduledoc """
  Round-robin балансировщик с поддержкой:
  - Weighted round-robin
  - Health checks
  - Метрики
  - Сброс счётчиков
  - Несколько стратегий
  """

  use GenServer
  require Logger

  alias ElixirClient.Client.Metrics

  @type strategy :: :simple | :weighted | :least_loaded
  @type instance :: %{
    host: String.t(),
    port: integer(),
    weight: pos_integer(),
    healthy: boolean(),
    last_check: integer()
  }

  # Клиентский API

  @doc """
  Запускает балансировщик.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Получает следующий инстанс для сервиса.
  """
  @spec next(String.t(), list(instance()), keyword()) :: instance()
  def next(service_name, instances, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :simple)
    GenServer.call(__MODULE__, {:next, service_name, instances, strategy})
  end

  @doc """
  Получает несколько инстансов.
  """
  @spec next_n(String.t(), list(instance()), integer(), keyword()) :: list(instance())
  def next_n(service_name, instances, n, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :simple)
    GenServer.call(__MODULE__, {:next_n, service_name, instances, n, strategy})
  end

  @doc """
  Сбрасывает счётчик для сервиса.
  """
  @spec reset(String.t()) :: :ok
  def reset(service_name) do
    GenServer.cast(__MODULE__, {:reset, service_name})
  end

  @doc """
  Получает статистику балансировщика.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # GenServer колбэки

  def init(opts) do
    state = %{
      counters: %{},
      total_calls: %{},
      failures: %{},
      last_reset: %{},
      strategy: Keyword.get(opts, :default_strategy, :simple),
      metrics_enabled: Keyword.get(opts, :metrics_enabled, true)
    }

    # Запускаем периодический сброс устаревших счётчиков
    schedule_cleanup()

    {:ok, state}
  end

  def handle_call({:next, service_name, instances, strategy}, _from, state) do
    result = select_instance(service_name, instances, strategy, state)

    case result do
      {:ok, instance} ->
        new_state = update_counters(service_name, instance, state)
        {:reply, instance, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:next_n, service_name, instances, n, strategy}, _from, state) do
    {results, new_state} = select_instances(service_name, instances, n, strategy, state)
    {:reply, results, new_state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      counters: state.counters,
      total_calls: state.total_calls,
      failures: state.failures,
      last_reset: state.last_reset
    }
    {:reply, stats, state}
  end

  def handle_cast({:reset, service_name}, state) do
    new_counters = Map.delete(state.counters, service_name)
    new_total = Map.delete(state.total_calls, service_name)
    new_failures = Map.delete(state.failures, service_name)
    last_reset = Map.put(state.last_reset, service_name, System.system_time(:millisecond))

    {:noreply, %{state |
      counters: new_counters,
      total_calls: new_total,
      failures: new_failures,
      last_reset: last_reset
    }}
  end

  def handle_info(:cleanup, state) do
    # Очищаем устаревшие счётчики
    one_hour_ago = System.system_time(:millisecond) - 3_600_000

    new_last_reset = Enum.filter(state.last_reset, fn {_, time} -> time > one_hour_ago end)
    |> Enum.into(%{})

    new_state = %{state | last_reset: new_last_reset}
    schedule_cleanup()
    {:noreply, new_state}
  end

  # Приватные функции

  defp select_instance(service_name, instances, strategy, state) do
    # Фильтруем только здоровые инстансы
    healthy_instances = Enum.filter(instances, &Map.get(&1, :healthy, true))

    if Enum.empty?(healthy_instances) do
      Logger.warning("No healthy instances for #{service_name}, using all")
      filtered_instances = instances
    else
      filtered_instances = healthy_instances
    end

    case strategy do
      :simple ->
        select_simple(service_name, filtered_instances, state)

      :weighted ->
        select_weighted(service_name, filtered_instances, state)

      :least_loaded ->
        select_least_loaded(service_name, filtered_instances, state)
    end
  end

  defp select_simple(service_name, instances, state) do
    current = Map.get(state.counters, service_name, 0)
    next = rem(current, length(instances))
    instance = Enum.at(instances, next)

    {:ok, instance}
  end

  defp select_weighted(service_name, instances, state) do
    # Weighted round-robin
    total_weight = Enum.reduce(instances, 0, fn i, acc -> acc + Map.get(i, :weight, 1) end)
    current = Map.get(state.counters, service_name, 0)
    position = rem(current, total_weight)

    select_by_weight(instances, position, 0)
  end

  defp select_by_weight([instance | rest], position, acc) do
    weight = Map.get(instance, :weight, 1)
    if position < acc + weight do
      {:ok, instance}
    else
      select_by_weight(rest, position, acc + weight)
    end
  end
  defp select_by_weight([], _, _), do: {:error, :no_instances}

  defp select_least_loaded(service_name, instances, state) do
    # Выбираем инстанс с наименьшим количеством вызовов
    calls = Map.get(state.total_calls, service_name, %{})

    instance = Enum.min_by(instances, fn i ->
      Map.get(calls, i.host <> ":" <> Integer.to_string(i.port), 0)
    end)

    {:ok, instance}
  end

  defp select_instances(service_name, instances, n, strategy, state) do
    {results, new_state} = Enum.reduce(1..n, {[], state}, fn _, {acc, s} ->
      case select_instance(service_name, instances, strategy, s) do
        {:ok, instance} ->
          new_s = update_counters(service_name, instance, s)
          {[instance | acc], new_s}
        {:error, _} ->
          {acc, s}
      end
    end)

    {Enum.reverse(results), new_state}
  end

  defp update_counters(service_name, instance, state) do
    # Обновляем основной счётчик
    current = Map.get(state.counters, service_name, 0)
    new_counters = Map.put(state.counters, service_name, current + 1)

    # Обновляем статистику по вызовам
    instance_key = instance.host <> ":" <> Integer.to_string(instance.port)
    service_calls = Map.get(state.total_calls, service_name, %{})
    instance_calls = Map.get(service_calls, instance_key, 0)
    new_service_calls = Map.put(service_calls, instance_key, instance_calls + 1)
    new_total_calls = Map.put(state.total_calls, service_name, new_service_calls)

    if state.metrics_enabled do
      Metrics.record_balance(service_name, instance_key)
    end

    %{state |
      counters: new_counters,
      total_calls: new_total_calls
    }
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 3_600_000)
  end
end
