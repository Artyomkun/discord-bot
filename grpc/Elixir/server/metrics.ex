defmodule ElixirServer.Metrics do
  use GenServer
  require Logger

  # ========== Client API ==========

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Запись метрики запроса
  def record_request(method, duration_ms, success \\ true, error \\ nil, service \\ "elixir") do
    GenServer.cast(__MODULE__, {:record_request, method, duration_ms, success, error, service})
  end

  # Увеличение счётчика
  def increment_counter(name, delta \\ 1) do
    GenServer.cast(__MODULE__, {:increment_counter, name, delta})
  end

  # Установка gauge
  def set_gauge(name, value) do
    GenServer.cast(__MODULE__, {:set_gauge, name, value})
  end

  # Запись в гистограмму
  def record_histogram(name, value) do
    GenServer.cast(__MODULE__, {:record_histogram, name, value})
  end

  # Добавление нерешённой задачи
  def add_unresolved_task(task) do
    GenServer.cast(__MODULE__, {:add_unresolved_task, task})
  end

  # Добавление критического алерта
  def add_critical_alert(alert) do
    GenServer.cast(__MODULE__, {:add_critical_alert, alert})
  end

  # Получение статистики
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Получение дашборда
  def get_dashboard do
    GenServer.call(__MODULE__, :get_dashboard)
  end

  # Получение метрик в формате Prometheus
  def get_prometheus_metrics do
    GenServer.call(__MODULE__, :get_prometheus_metrics)
  end

  # Сброс метрик
  def reset do
    GenServer.cast(__MODULE__, :reset)
  end

  # ========== Server Callbacks ==========

  def init(opts) do
    max_history = opts[:max_history] || 10_000

    state = %{
      # Основные метрики
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      start_time: :os.system_time(:seconds),

      # История запросов
      requests: [],
      max_history: max_history,

      # Статистика по методам
      method_stats: %{},

      # Счётчики и gauges
      counters: %{},
      gauges: %{},

      # Гистограммы
      histograms: %{},

      # Ошибки и задачи
      error_records: [],
      unresolved_tasks: %{},
      critical_alerts: [],

      # Пороги для алертов
      thresholds: %{
        error_rate_warning: 0.05,
        error_rate_critical: 0.10,
        high_latency_ms: 5000,
        unresolved_alert_threshold: 3,
        critical_error_window: 60,
        critical_error_threshold: 3
      },

      # Статусы сервисов
      service_statuses: %{
        go: %{status: :unknown, last_heartbeat: nil, latency_ms: 0},
        python: %{status: :unknown, last_heartbeat: nil, latency_ms: 0},
        audio: %{status: :unknown, last_heartbeat: nil, latency_ms: 0},
        gateway: %{status: :unknown, last_heartbeat: nil, latency_ms: 0}
      }
    }

    # Запускаем фоновую обработку
    schedule_metrics_processing()
    schedule_alert_check()

    {:ok, state}
  end

  def handle_cast({:record_request, method, duration_ms, success, error, service}, state) do
    now = :os.system_time(:seconds)

    # Обновляем общую статистику
    total_requests = state.total_requests + 1
    successful_requests = if success, do: state.successful_requests + 1, else: state.successful_requests
    failed_requests = if success, do: state.failed_requests, else: state.failed_requests + 1

    # Добавляем в историю
    request = %{
      method: method,
      duration_ms: duration_ms,
      success: success,
      error: error,
      service: service,
      timestamp: now
    }

    requests = [request | state.requests] |> Enum.take(state.max_history)

    # Обновляем статистику по методу
    method_key = "#{service}:#{method}"
    method_stats = update_method_stats(state.method_stats, method_key, duration_ms, success, error)

    # Обновляем гистограмму
    histograms = update_histogram(state.histograms, "request_duration_ms", duration_ms, state.max_history)

    # Если ошибка, записываем в error_records
    error_records = if not success and error do
      error_record = %{
        timestamp: now,
        method: method,
        error: error,
        service: service,
        resolved: false
      }
      [error_record | state.error_records] |> Enum.take(state.max_history)
    else
      state.error_records
    end

    new_state = %{state |
      total_requests: total_requests,
      successful_requests: successful_requests,
      failed_requests: failed_requests,
      requests: requests,
      method_stats: method_stats,
      histograms: histograms,
      error_records: error_records
    }

    {:noreply, new_state}
  end

  def handle_cast({:increment_counter, name, delta}, state) do
    counters = Map.update(state.counters, name, delta, &(&1 + delta))
    {:noreply, %{state | counters: counters}}
  end

  def handle_cast({:set_gauge, name, value}, state) do
    gauges = Map.put(state.gauges, name, value)
    {:noreply, %{state | gauges: gauges}}
  end

  def handle_cast({:record_histogram, name, value}, state) do
    histograms = update_histogram(state.histograms, name, value, state.max_history)
    {:noreply, %{state | histograms: histograms}}
  end

  def handle_cast({:add_unresolved_task, task}, state) do
    Logger.warning("📥 Unresolved task: #{task.method} - #{String.slice(task.error, 0, 100)}")

    unresolved_tasks = Map.put(state.unresolved_tasks, task.task_id, task)

    # Проверяем порог
    if map_size(unresolved_tasks) >= state.thresholds.unresolved_alert_threshold do
      Logger.critical("🚨 Too many unresolved tasks: #{map_size(unresolved_tasks)}")
    end

    {:noreply, %{state | unresolved_tasks: unresolved_tasks}}
  end

  def handle_cast({:add_critical_alert, alert}, state) do
    Logger.critical("🔴 Critical alert: #{alert.message}")

    critical_alerts = [alert | state.critical_alerts] |> Enum.take(100)

    {:noreply, %{state | critical_alerts: critical_alerts}}
  end

  def handle_cast(:reset, _state) do
    {:noreply, init([])}
  end

  def handle_call(:get_stats, _from, state) do
    uptime = :os.system_time(:seconds) - state.start_time

    # Вычисляем RPS за последнюю минуту
    now = :os.system_time(:seconds)
    recent_requests = Enum.filter(state.requests, fn r ->
      now - r.timestamp <= 60
    end)
    rps = length(recent_requests) / 60

    # Вычисляем среднюю задержку
    avg_duration = if length(recent_requests) > 0 do
      Enum.sum(Enum.map(recent_requests, &(&1.duration_ms))) / length(recent_requests)
    else
      0.0
    end

    stats = %{
      uptime_seconds: uptime,
      total_requests: state.total_requests,
      successful_requests: state.successful_requests,
      failed_requests: state.failed_requests,
      success_rate: if state.total_requests > 0 do
        state.successful_requests / state.total_requests * 100
      else
        0.0
      end,
      error_rate: if state.total_requests > 0 do
        state.failed_requests / state.total_requests * 100
      else
        0.0
      end,
      requests_per_second: rps,
      avg_response_time_ms: avg_duration,
      total_errors: length(state.error_records),
      unresolved_tasks: map_size(state.unresolved_tasks),
      critical_alerts: length(state.critical_alerts),
      methods: state.method_stats,
      counters: state.counters,
      gauges: state.gauges,
      service_statuses: state.service_statuses
    }

    {:reply, stats, state}
  end

  def handle_call(:get_dashboard, _from, state) do
    dashboard = %{
      overview: %{
        total_requests: state.total_requests,
        successful: state.successful_requests,
        failed: state.failed_requests,
        uptime: :os.system_time(:seconds) - state.start_time,
        unresolved_tasks: map_size(state.unresolved_tasks)
      },
      recent_errors: Enum.take(state.error_records, 20),
      recent_requests: Enum.take(state.requests, 20),
      method_stats: state.method_stats,
      service_statuses: state.service_statuses,
      critical_alerts: state.critical_alerts
    }

    {:reply, dashboard, state}
  end

  def handle_call(:get_prometheus_metrics, _from, state) do
    metrics = format_prometheus(state)
    {:reply, metrics, state}
  end

  def handle_info(:process_metrics, state) do
    # Анализируем ошибки и принимаем решения
    state = analyze_errors(state)
    schedule_metrics_processing()
    {:noreply, state}
  end

  def handle_info(:check_alerts, state) do
    state = check_thresholds(state)
    schedule_alert_check()
    {:noreply, state}
  end

  # ========== Внутренние функции ==========

  defp update_method_stats(method_stats, method, duration_ms, success, error) do
    stats = Map.get(method_stats, method, %{
      total: 0,
      success: 0,
      failed: 0,
      total_duration: 0,
      min_duration: nil,
      max_duration: 0,
      last_error: nil
    })

    total = stats.total + 1
    success_count = if success, do: stats.success + 1, else: stats.success
    failed_count = if success, do: stats.failed, else: stats.failed + 1
    total_duration = stats.total_duration + duration_ms

    min_duration = case stats.min_duration do
      nil -> duration_ms
      current -> min(current, duration_ms)
    end

    max_duration = max(stats.max_duration, duration_ms)

    last_error = if not success, do: error, else: stats.last_error

    Map.put(method_stats, method, %{
      total: total,
      success: success_count,
      failed: failed_count,
      total_duration: total_duration,
      min_duration: min_duration,
      max_duration: max_duration,
      avg_duration: total_duration / total,
      last_error: last_error
    })
  end

  defp update_histogram(histograms, name, value, max_size) do
    values = Map.get(histograms, name, [])
    new_values = [value | values] |> Enum.take(max_size)
    Map.put(histograms, name, new_values)
  end

  defp analyze_errors(state) do
    # Анализируем последние ошибки
    now = :os.system_time(:seconds)
    window_start = now - state.thresholds.critical_error_window

    errors_in_window = Enum.count(state.error_records, fn e ->
      e.timestamp > window_start and not e.resolved
    end)

    if errors_in_window >= state.thresholds.critical_error_threshold do
      Logger.critical("🚨 Critical error rate: #{errors_in_window} errors in #{state.thresholds.critical_error_window}s")

      # Отправляем команду на переподключение
      ElixirServer.Pool.send_command(:go, "reconnect", %{reason: "critical_error_rate"})
    end

    state
  end

  defp check_thresholds(state) do
    # Проверяем error rate
    if state.total_requests > 0 do
      error_rate = state.failed_requests / state.total_requests

      if error_rate > state.thresholds.error_rate_critical do
        Logger.critical("🔴 Critical error rate: #{error_rate * 100:.2f}%")
        ElixirServer.Pool.send_command(:go, "report_status", %{reason: "high_error_rate"})
      elseif error_rate > state.thresholds.error_rate_warning do
        Logger.warning("⚠️ High error rate: #{error_rate * 100:.2f}%")
      end
    end

    # Проверяем задержку
    recent_requests = Enum.filter(state.requests, fn r ->
      :os.system_time(:seconds) - r.timestamp <= 60
    end)

    if length(recent_requests) > 0 do
      avg_latency = Enum.sum(Enum.map(recent_requests, &(&1.duration_ms))) / length(recent_requests)

      if avg_latency > state.thresholds.high_latency_ms do
        Logger.warning("⚠️ High latency: #{avg_latency:.2f}ms")
        ElixirServer.Pool.send_command(:go, "increase_timeout", %{reason: "high_latency"})
      end
    end

    state
  end

  defp format_prometheus(state) do
    uptime = :os.system_time(:seconds) - state.start_time
    error_rate = if state.total_requests > 0 do
      state.failed_requests / state.total_requests * 100
    else
      0.0
    end

    """
    # HELP elixir_uptime_seconds Elixir gateway uptime in seconds
    # TYPE elixir_uptime_seconds gauge
    elixir_uptime_seconds #{uptime}

    # HELP elixir_requests_total Total requests processed
    # TYPE elixir_requests_total counter
    elixir_requests_total #{state.total_requests}

    # HELP elixir_requests_successful Successful requests
    # TYPE elixir_requests_successful counter
    elixir_requests_successful #{state.successful_requests}

    # HELP elixir_requests_failed Failed requests
    # TYPE elixir_requests_failed counter
    elixir_requests_failed #{state.failed_requests}

    # HELP elixir_error_rate Error rate percentage
    # TYPE elixir_error_rate gauge
    elixir_error_rate #{error_rate}

    # HELP elixir_unresolved_tasks Unresolved tasks from services
    # TYPE elixir_unresolved_tasks gauge
    elixir_unresolved_tasks #{map_size(state.unresolved_tasks)}

    # HELP elixir_critical_alerts Critical alerts received
    # TYPE elixir_critical_alerts counter
    elixir_critical_alerts #{length(state.critical_alerts)}

    # HELP elixir_requests_per_second Requests per second
    # TYPE elixir_requests_per_second gauge
    elixir_requests_per_second #{calculate_rps(state.requests)}

    #{format_method_metrics(state.method_stats)}
    #{format_counter_metrics(state.counters)}
    #{format_gauge_metrics(state.gauges)}
    #{format_histogram_metrics(state.histograms)}
    """
  end

  defp calculate_rps(requests) do
    now = :os.system_time(:seconds)
    recent = Enum.count(requests, fn r -> now - r.timestamp <= 60 end)
    recent / 60
  end

  defp format_method_metrics(methods) do
    Enum.map(methods, fn {method, stats} ->
      method_safe = String.replace(method, ":", "_")
      """
      # HELP elixir_method_#{method_safe}_total Total calls to #{method}
      # TYPE elixir_method_#{method_safe}_total counter
      elixir_method_#{method_safe}_total #{stats.total}

      # HELP elixir_method_#{method_safe}_avg_duration_ms Average duration for #{method}
      # TYPE elixir_method_#{method_safe}_avg_duration_ms gauge
      elixir_method_#{method_safe}_avg_duration_ms #{stats.avg_duration}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_counter_metrics(counters) do
    Enum.map(counters, fn {name, value} ->
      name_safe = String.replace(name, ":", "_")
      """
      # HELP elixir_counter_#{name_safe} Counter metric
      # TYPE elixir_counter_#{name_safe} counter
      elixir_counter_#{name_safe} #{value}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_gauge_metrics(gauges) do
    Enum.map(gauges, fn {name, value} ->
      name_safe = String.replace(name, ":", "_")
      """
      # HELP elixir_gauge_#{name_safe} Gauge metric
      # TYPE elixir_gauge_#{name_safe} gauge
      elixir_gauge_#{name_safe} #{value}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_histogram_metrics(histograms) do
    Enum.map(histograms, fn {name, values} ->
      if length(values) > 0 do
        sorted = Enum.sort(values)
        p50 = percentile(sorted, 50)
        p95 = percentile(sorted, 95)
        p99 = percentile(sorted, 99)

        """
        # HELP elixir_histogram_#{name} Histogram metric
        # TYPE elixir_histogram_#{name} summary
        elixir_histogram_#{name}_count #{length(values)}
        elixir_histogram_#{name}_sum #{Enum.sum(values)}
        elixir_histogram_#{name}_p50 #{p50}
        elixir_histogram_#{name}_p95 #{p95}
        elixir_histogram_#{name}_p99 #{p99}
        """
      else
        ""
      end
    end)
    |> Enum.join("\n")
  end

  defp percentile(sorted, p) do
    idx = round(length(sorted) * p / 100)
    if idx >= length(sorted) do
      List.last(sorted)
    else
      Enum.at(sorted, idx)
    end
  end

  defp schedule_metrics_processing do
    Process.send_after(self(), :process_metrics, 10_000)
  end

  defp schedule_alert_check do
    Process.send_after(self(), :check_alerts, 30_000)
  end
end
