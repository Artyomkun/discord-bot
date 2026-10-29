defmodule ElixirClient.Client.Metrics do
  @moduledoc """
  Сбор метрик gRPC клиента.
  Хранит в ETS для быстрого доступа и отправляет в Telemetry.

  Поддерживает:
  - Метрики вызовов (длительность, успешность)
  - Метрики пула (checkout/checkin)
  - Гистограммы
  - Percentiles
  - Метрики по сервисам и методам
  - Сборщик мусора для старых метрик
  """

  use GenServer
  require Logger

  alias GRPC.RPCError
  alias MusicCore.AudioStreaming.Processor

  @table_name :grpc_client_metrics
  @histogram_table :grpc_histograms
  @max_history_size 1000
  @cleanup_interval 300_000 # 5 минут

  # Типы
  @type metric_key :: {String.t(), atom()}
  @type metric_stats :: %{
    count: non_neg_integer(),
    successes: non_neg_integer(),
    failures: non_neg_integer(),
    total_duration: integer(),
    min_duration: integer(),
    max_duration: integer(),
    last_seen: integer()
  }

  @type histogram :: [non_neg_integer()]

  # Клиентский API

  @doc """
  Запускает менеджер метрик.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Записывает метрику вызова.
  """
  def record_call(service, method, result, duration) do
    success? = match?({:ok, _, _}, result)
    timestamp = System.system_time(:millisecond)

    # Отправляем в Telemetry
    :telemetry.execute([:music_core, :grpc, :call], %{
      duration: System.convert_time_unit(duration, :native, :microsecond),
      success: if(success?, do: 1, else: 0)
    }, %{
      service: service,
      method: method
    })

    # Сохраняем в ETS
    key = {service, method}
    current = :ets.lookup(@table_name, key)

    stats = case current do
      [{_, old_stats}] ->
        %{
          count: old_stats.count + 1,
          successes: old_stats.successes + (if(success?, do: 1, else: 0)),
          failures: old_stats.failures + (if(success?, do: 0, else: 1)),
          total_duration: old_stats.total_duration + duration,
          min_duration: min(old_stats.min_duration, duration),
          max_duration: max(old_stats.max_duration, duration),
          last_seen: timestamp
        }
      [] ->
        %{
          count: 1,
          successes: if(success?, do: 1, else: 0),
          failures: if(success?, do: 0, else: 1),
          total_duration: duration,
          min_duration: duration,
          max_duration: duration,
          last_seen: timestamp
        }
    end

    :ets.insert(@table_name, {key, stats})

    # Сохраняем в гистограмму
    record_histogram(service, method, duration)
  end

  @doc """
  Записывает метрику checkout из пула.
  """
  def record_checkout(service) do
    :telemetry.execute([:music_core, :grpc, :pool, :checkout], %{
      success: 1
    }, %{service: service})

    update_pool_metric(service, :checkouts, 1)
  end

  @doc """
  Записывает метрику неудачного checkout.
  """
  def record_checkout_failure(service, reason) do
    :telemetry.execute([:music_core, :grpc, :pool, :checkout], %{
      success: 0,
      failure: 1
    }, %{service: service, reason: reason})

    update_pool_metric(service, :checkout_failures, 1)
    update_pool_metric(service, :"checkout_failures_#{reason}", 1)
  end

  @doc """
  Записывает метрику checkin.
  """
  def record_checkin(service) do
    :telemetry.execute([:music_core, :grpc, :pool, :checkin], %{
      count: 1
    }, %{service: service})

    update_pool_metric(service, :checkins, 1)
  end

  @doc """
  Записывает метрику балансировки.
  """
  def record_balance(service, instance) do
    :telemetry.execute([:music_core, :grpc, :balance], %{
      count: 1
    }, %{
      service: service,
      instance: instance
    })

    update_balance_metric(service, instance)
  end

  @doc """
  Записывает метрику ошибки.
  """
  def record_error(service, method, error) do
    :telemetry.execute([:music_core, :grpc, :error], %{
      count: 1
    }, %{
      service: service,
      method: method,
      error: inspect(error)
    })

    update_error_metric(service, method, error)
  end

  @doc """
  Получает все метрики.
  """
  def get_all do
    stats = :ets.tab2list(@table_name)
    |> Enum.map(fn {{service, method}, data} ->
      {service, method, enrich_stats(data)}
    end)

    # Группируем по сервисам
    Enum.group_by(stats, fn {service, _, _} -> service end, fn {_, method, data} ->
      {method, data}
    end)
  end

  @doc """
  Получает метрики для сервиса.
  """
  def get_for_service(service) do
    get_all()
    |> Map.get(service, %{})
  end

  @doc """
  Получает метрики для метода.
  """
  def get_for_method(service, method) do
    case :ets.lookup(@table_name, {service, method}) do
      [{_, data}] -> enrich_stats(data)
      [] -> nil
    end
  end

  @doc """
  Получает гистограмму для метода.
  """
  def get_histogram(service, method, buckets \\ [10, 50, 100, 500, 1000, 5000]) do
    key = {service, method}
    case :ets.lookup(@histogram_table, key) do
      [{_, hist}] ->
        calculate_percentiles(hist, buckets)
      [] ->
        %{}
    end
  end

  @doc """
  Получает метрики пула.
  """
  def get_pool_metrics(service) do
    case :ets.lookup(@table_name, {:pool, service}) do
      [{_, metrics}] -> metrics
      [] -> %{}
    end
  end

  @doc """
  Сбрасывает все метрики.
  """
  def reset do
    :ets.delete_all_objects(@table_name)
    :ets.delete_all_objects(@histogram_table)
    :ok
  end

  @doc """
  Сбрасывает метрики для сервиса.
  """
  def reset_service(service) do
    # Удаляем все метрики для сервиса
    :ets.foldl(fn
      {{s, _}, _} = key when s == service ->
        :ets.delete(@table_name, key)
      {_, _, _} = key when elem(key, 0) == service ->
        :ets.delete(@table_name, key)
      _ -> :ok
    end, :ok, @table_name)

    :ok
  end

  # GenServer колбэки

  def init(_opts) do
    # Создаём ETS таблицы
    :ets.new(@table_name, [:named_table, :public, :set])
    :ets.new(@histogram_table, [:named_table, :public, :set])

    # Запускаем периодическую очистку
    schedule_cleanup()

    {:ok, %{}}
  end

  def handle_info(:cleanup, state) do
    # Удаляем старые записи
    cleanup_old_metrics()
    schedule_cleanup()
    {:noreply, state}
  end

  # Приватные функции

  defp record_histogram(service, method, duration) do
    key = {service, method}
    duration_us = System.convert_time_unit(duration, :native, :microsecond)

    :ets.update_counter(@histogram_table, key, {2, 1}, {key, []})

    current = case :ets.lookup(@histogram_table, key) do
      [{_, hist}] -> hist
      _ -> []
    end

    new_hist = [duration_us | current] |> Enum.take(@max_history_size)
    :ets.insert(@histogram_table, {key, new_hist})
  end

  defp update_pool_metric(service, metric, value) do
    key = {:pool, service}
    current = case :ets.lookup(@table_name, key) do
      [{_, metrics}] -> metrics
      [] -> %{}
    end

    new_metrics = Map.update(current, metric, value, &(&1 + value))
    :ets.insert(@table_name, {key, new_metrics})
  end

  defp update_balance_metric(service, instance) do
    key = {:balance, service}
    current = case :ets.lookup(@table_name, key) do
      [{_, metrics}] -> metrics
      [] -> %{}
    end

    instance_metrics = Map.get(current, instance, %{count: 0})
    new_instance = %{instance_metrics | count: instance_metrics.count + 1}
    new_metrics = Map.put(current, instance, new_instance)
    :ets.insert(@table_name, {key, new_metrics})
  end

  defp update_error_metric(service, method, error) do
    key = {:error, service, method}
    error_type = error_type(error)

    current = case :ets.lookup(@table_name, key) do
      [{_, counts}] -> counts
      [] -> %{}
    end

    new_counts = Map.update(current, error_type, 1, &(&1 + 1))
    :ets.insert(@table_name, {key, new_counts})
  end

  defp error_type(%RPCError{code: code}), do: "grpc_#{code}"
  defp error_type(%{__struct__: struct}), do: struct |> to_string() |> String.replace("Elixir.", "")
  defp error_type(other), do: inspect(other)

  defp enrich_stats(data) do
    avg_duration = if data.count > 0 do
      System.convert_time_unit(round(data.total_duration / data.count), :native, :microsecond)
    else
      0
    end

    %{
      count: data.count,
      success_rate: if(data.count > 0, do: data.successes / data.count, else: 0.0),
      success_percent: if(data.count > 0, do: 100 * data.successes / data.count, else: 0.0),
      failures: data.failures,
      avg_duration_us: avg_duration,
      min_duration_us: System.convert_time_unit(data.min_duration, :native, :microsecond),
      max_duration_us: System.convert_time_unit(data.max_duration, :native, :microsecond),
      last_seen: data.last_seen
    }
  end

  defp calculate_percentiles(histogram, buckets) do
    sorted = Enum.sort(histogram)
    len = length(sorted)

    Enum.map(buckets, fn percentile ->
      index = round(len * percentile / 100) - 1
      value = if index >= 0, do: Enum.at(sorted, index), else: 0
      {:"p#{percentile}", value}
    end)
    |> Enum.into(%{})
  end

  defp cleanup_old_metrics do
    one_hour_ago = System.system_time(:millisecond) - 3_600_000

    # Удаляем старые записи
    :ets.foldl(fn
      {key, %{last_seen: last}} = entry when last < one_hour_ago ->
        :ets.delete_object(@table_name, entry)
      _ -> :ok
    end, :ok, @table_name)

    # Очищаем старые гистограммы (просто лишние данные)
    :ets.foldl(fn
      {key, hist} = entry when length(hist) > @max_history_size ->
        new_hist = Enum.take(hist, @max_history_size)
        :ets.insert(@histogram_table, {key, new_hist})
      _ -> :ok
    end, :ok, @histogram_table)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
