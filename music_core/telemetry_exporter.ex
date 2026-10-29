defmodule MusicCore.TelemetryExporter do
  @moduledoc """
  Сбор и экспорт метрик из Telemetry в различные форматы и системы.

  Поддерживает:
  - Prometheus (для сбора метрик)
  - StatsD (для дашбордов)
  - JSON-логи (для отладки)
  - Файловый экспорт (для анализа)
  - InfluxDB (для временных рядов)
  """

  use GenServer
  require Logger

  # Клиентский API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Получить текущие метрики
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Сбросить все счётчики
  """
  def reset_metrics do
    GenServer.cast(__MODULE__, :reset_metrics)
  end

  @doc """
  Экспортировать метрики в указанный формат
  """
  def export(format \\ :prometheus) do
    GenServer.call(__MODULE__, {:export, format})
  end

  def init(opts) do
    # Прикрепляем обработчики Telemetry
    :telemetry.attach_many(
      "music-core-metrics",
      [
        [:music_core, :processor, :task_completed],
        [:music_core, :processor, :task_failed],
        [:music_core, :processor, :task_started],
        [:music_core, :processor, :queue],
        [:music_core, :processor, :metrics],
        [:music_core, :dsp, :call],
        [:music_core, :dsp, :nif, :loaded],
        [:music_core, :qos, :task_started],
        [:music_core, :cache, :hit],
        [:music_core, :cache, :miss],
        [:music_core, :cache, :put],
        [:music_core, :circuit_breaker, :trip],
        [:music_core, :circuit_breaker, :reset],
        [:music_core, :backpressure, :reject],
        [:music_core, :backpressure, :accept]
      ],
      &handle_telemetry/4,
      nil
    )

    state = %{
      counters: %{},
      gauges: %{},
      histograms: %{},
      summaries: %{},
      timers: %{},
      last_flush: System.system_time(:millisecond),
      flush_interval: Keyword.get(opts, :flush_interval, 10_000)
    }

    schedule_flush(state.flush_interval)
    {:ok, state}
  end

  def handle_call(:get_metrics, from, state) do
    {:reply, state, state}
  end

  def handle_call({:export, format}, from, state) do
    exported = export_metrics(state, format)
    {:reply, exported, state}
  end

  def handle_cast(:reset_metrics, state) do
    new_state = %{
      state |
      counters: %{},
      gauges: %{},
      histograms: %{},
      summaries: %{},
      timers: %{},
      last_flush: System.system_time(:millisecond)
    }
    {:noreply, new_state}
  end

  def handle_info(:flush_metrics, state) do
    case Application.get_env(:music_core, :metrics_export, []) do
      [] -> :ok
      targets ->
        Enum.each(targets, fn target ->
          export_to_target(state, target)
        end)
    end

    schedule_flush(state.flush_interval)
    {:noreply, state}
  end

  def terminate(reason, state) do
    :telemetry.detach("music-core-metrics")
    Logger.info("TelemetryExporter terminated: #{inspect(reason)}")
    :ok
  end

  # ========== ОБРАБОТКА TELEMETRY ==========

  defp handle_telemetry([:music_core, :processor, :task_completed], measurements, metadata, config) do
    update_counter(:tasks_completed_total, 1)
    update_histogram(:task_duration_ms, Map.get(measurements, :processing_time, 0))
    update_gauge(:active_tasks, Map.get(metadata, :active_tasks, 0))
  end

  defp handle_telemetry([:music_core, :processor, :task_failed], measurements, metadata, config) do
    update_counter(:tasks_failed_total, 1)
    reason = Map.get(metadata, :reason, :unknown)
    update_counter([:tasks_failed, reason], 1)
  end

  defp handle_telemetry([:music_core, :processor, :task_started], measurements, metadata, config) do
    update_gauge(:active_tasks, Map.get(metadata, :active_tasks, 0))
    priority = Map.get(metadata, :priority, :normal)
    update_counter([:tasks_started, priority], 1)
  end

  defp handle_telemetry([:music_core, :processor, :queue], measurements, metadata, config) do
    update_gauge(:queue_size, Map.get(measurements, :size, 0))
    priority = Map.get(metadata, :priority, :normal)
    update_gauge([:queue_size, priority], Map.get(measurements, :size, 0))
  end

  defp handle_telemetry([:music_core, :processor, :metrics], measurements, metadata, config) do
    update_gauge(:throughput_1min, Map.get(measurements, :throughput, 0))
    update_gauge(:error_rate, Map.get(measurements, :error_rate, 0))
    update_gauge(:avg_response_time, Map.get(measurements, :avg_time, 0))
  end

  defp handle_telemetry([:music_core, :dsp, :call], measurements, metadata, config) do
    effect = Map.get(metadata, :effect, :unknown)
    update_histogram([:dsp, :duration, effect], Map.get(measurements, :duration, 0))
    update_counter([:dsp, :calls, effect], 1)

    if Map.get(measurements, :success, false) do
      update_counter([:dsp, :success, effect], 1)
    else
      update_counter([:dsp, :errors, effect], 1)
    end
  end

  defp handle_telemetry([:music_core, :dsp, :nif, :loaded], measurements, metadata, config) do
    success = if Map.get(measurements, :success, false), do: 1, else: 0
    update_gauge(:nif_loaded, success)
    update_histogram(:nif_load_time, Map.get(measurements, :load_time_ms, 0))
  end

  defp handle_telemetry([:music_core, :qos, :task_started], measurements, metadata, config) do
    profile = Map.get(metadata, :profile, :balanced)
    update_counter([:qos, :tasks, profile], 1)
  end

  defp handle_telemetry([:music_core, :cache, :hit], measurements, metadata, config) do
    level = Map.get(metadata, :level, :unknown)
    update_counter([:cache, :hits, level], 1)
  end

  defp handle_telemetry([:music_core, :cache, :miss], measurements, metadata, config) do
    level = Map.get(metadata, :level, :unknown)
    update_counter([:cache, :misses, level], 1)
  end

  defp handle_telemetry([:music_core, :cache, :put], measurements, metadata, config) do
    level = Map.get(metadata, :level, :unknown)
    update_counter([:cache, :puts, level], 1)
    update_histogram([:cache, :size, level], Map.get(measurements, :size, 0))
  end

  defp handle_telemetry([:music_core, :circuit_breaker, :trip], measurements, metadata, config) do
    circuit = Map.get(metadata, :circuit, :unknown)
    update_counter([:circuit_breaker, :trips, circuit], 1)
  end

  defp handle_telemetry([:music_core, :circuit_breaker, :reset], measurements, metadata, config) do
    circuit = Map.get(metadata, :circuit, :unknown)
    update_counter([:circuit_breaker, :resets, circuit], 1)
  end

  defp handle_telemetry([:music_core, :backpressure, :reject], measurements, metadata, config) do
    priority = Map.get(metadata, :priority, :normal)
    update_counter([:backpressure, :rejects, priority], 1)
  end

  defp handle_telemetry([:music_core, :backpressure, :accept], measurements, metadata, config) do
    priority = Map.get(metadata, :priority, :normal)
    update_counter([:backpressure, :accepts, priority], 1)
  end

  defp handle_telemetry(event, measurements, metadata, config) do
    Logger.debug("Unhandled telemetry event: #{inspect(event)}")
    :ok
  end

  # ========== ОБНОВЛЕНИЕ МЕТРИК ==========

  defp update_counter(name, increment) do
    case :persistent_term.get(:telemetry_state, nil) do
      nil -> :ok
      state ->
        new_counters = Map.update(state.counters, name, increment, fn val -> val + increment end)
        new_state = %{state | counters: new_counters}
        :persistent_term.put(:telemetry_state, new_state)
    end
  end

  defp update_gauge(name, value) do
    case :persistent_term.get(:telemetry_state, nil) do
      nil -> :ok
      state ->
        new_gauges = Map.put(state.gauges, name, value)
        new_state = %{state | gauges: new_gauges}
        :persistent_term.put(:telemetry_state, new_state)
    end
  end

  defp update_histogram(name, value) do
    case :persistent_term.get(:telemetry_state, nil) do
      nil -> :ok
      state ->
        current = Map.get(state.histograms, name, [])
        new = [value | current] |> Enum.take(1000)
        new_histograms = Map.put(state.histograms, name, new)
        new_state = %{state | histograms: new_histograms}
        :persistent_term.put(:telemetry_state, new_state)
    end
  end

  # ========== ЭКСПОРТ МЕТРИК ==========

  defp export_metrics(state, format) do
    counters = state.counters
    gauges = state.gauges
    histograms = state.histograms

    case format do
      :prometheus -> export_prometheus(counters, gauges, histograms)
      :json -> export_json(counters, gauges, histograms)
      :statsd -> export_statsd(counters, gauges, histograms)
      :influxdb -> export_influxdb(counters, gauges, histograms)
      :log -> export_log(counters, gauges, histograms)
    end
  end

  defp export_prometheus(counters, gauges, histograms) do
    lines = []

    lines = Enum.reduce(counters, lines, fn {name, value}, acc ->
      name_str = format_prometheus_name(name)
      ["# TYPE #{name_str} counter", "# HELP #{name_str} #{name_str} counter", "#{name_str} #{value}", "" | acc]
    end)

    lines = Enum.reduce(gauges, lines, fn {name, value}, acc ->
      name_str = format_prometheus_name(name)
      ["# TYPE #{name_str} gauge", "# HELP #{name_str} #{name_str} gauge", "#{name_str} #{value}", "" | acc]
    end)

    lines = Enum.reduce(histograms, lines, fn {name, values}, acc ->
      name_str = format_prometheus_name(name)
      ["# TYPE #{name_str} histogram", "# HELP #{name_str} #{name_str} histogram" | acc]
    end)

    Enum.join(Enum.reverse(lines), "\n")
  end

  defp export_json(counters, gauges, histograms) do
    data = %{
      counters: counters,
      gauges: gauges,
      histograms: Enum.map(histograms, fn {name, values} ->
        {name, %{
          count: length(values),
          sum: Enum.sum(values),
          avg: avg(values),
          min: min_value(values),
          max: max_value(values)
        }}
      end) |> Enum.into(%{}),
      timestamp: System.system_time(:millisecond)
    }

    Jason.encode!(data, pretty: true)
  end

  defp export_statsd(counters, gauges, histograms) do
    lines = []

    lines = Enum.reduce(counters, lines, fn {name, value}, acc ->
      name_str = format_statsd_name(name)
      ["#{name_str}:#{value}|c" | acc]
    end)

    lines = Enum.reduce(gauges, lines, fn {name, value}, acc ->
      name_str = format_statsd_name(name)
      ["#{name_str}:#{value}|g" | acc]
    end)

    Enum.join(Enum.reverse(lines), "\n")
  end

  defp export_influxdb(counters, gauges, histograms) do
    timestamp = System.system_time(:nanosecond)
    lines = []

    lines = Enum.reduce(counters, lines, fn {name, value}, acc ->
      name_str = format_influxdb_name(name)
      ["#{name_str} value=#{value} #{timestamp}" | acc]
    end)

    lines = Enum.reduce(gauges, lines, fn {name, value}, acc ->
      name_str = format_influxdb_name(name)
      ["#{name_str} value=#{value} #{timestamp}" | acc]
    end)

    Enum.join(Enum.reverse(lines), "\n")
  end

  defp export_log(counters, gauges, histograms) do
    %{
      counters: counters,
      gauges: gauges,
      histograms: Enum.map(histograms, fn {name, values} ->
        {name, %{count: length(values), avg: avg(values)}}
      end) |> Enum.into(%{}),
      timestamp: DateTime.utc_now()
    }
    |> inspect()
  end

  # ========== ФОРМАТИРОВАНИЕ ==========

  defp format_prometheus_name({key, sub}) when is_atom(key) and is_atom(sub) do
    "music_core_#{key}_#{sub}"
  end
  defp format_prometheus_name({key, sub, sub2}) when is_atom(key) and is_atom(sub) and is_atom(sub2) do
    "music_core_#{key}_#{sub}_#{sub2}"
  end
  defp format_prometheus_name(name) when is_atom(name) do
    "music_core_#{name}"
  end
  defp format_prometheus_name(name) when is_list(name) do
    "music_core_" <> Enum.map_join(name, "_", &to_string/1)
  end

  defp format_statsd_name({key, sub}) do
    "music_core.#{key}.#{sub}"
  end
  defp format_statsd_name({key, sub, sub2}) do
    "music_core.#{key}.#{sub}.#{sub2}"
  end
  defp format_statsd_name(name) when is_atom(name) do
    "music_core.#{name}"
  end
  defp format_statsd_name(name) when is_list(name) do
    "music_core." <> Enum.map_join(name, ".", &to_string/1)
  end

  defp format_influxdb_name({key, sub}) do
    "music_core_#{key}_#{sub}"
  end
  defp format_influxdb_name({key, sub, sub2}) do
    "music_core_#{key}_#{sub}_#{sub2}"
  end
  defp format_influxdb_name(name) when is_atom(name) do
    "music_core_#{name}"
  end

  # ========== УТИЛИТЫ ==========

  defp avg([]), do: 0
  defp avg(list), do: Enum.sum(list) / length(list)

  defp min_value([]), do: 0
  defp min_value(list), do: Enum.min(list)

  defp max_value([]), do: 0
  defp max_value(list), do: Enum.max(list)

  defp schedule_flush(interval) do
    Process.send_after(self(), :flush_metrics, interval)
  end

  defp export_to_target(state, {:prometheus, port}) do
    metrics = export_prometheus(state.counters, state.gauges, state.histograms)
    Task.start(fn ->
      try do
        Req.post("http://localhost:#{port}/metrics/job/music_core", body: metrics)
      rescue
        e -> Logger.warning("Prometheus export failed: #{inspect(e)}")
      end
    end)
    :ok
  end

  defp export_to_target(state, {:statsd, host, port}) do
    metrics = export_statsd(state.counters, state.gauges, state.histograms)
    Task.start(fn ->
      try do
        {:ok, socket} = :gen_udp.open(0, [:binary])
        metrics
        |> String.split("\n")
        |> Enum.each(fn metric ->
          if metric != "" do
            :gen_udp.send(socket, String.to_charlist(host), port, metric)
          end
        end)
        :gen_udp.close(socket)
      rescue
        e -> Logger.warning("StatsD export failed: #{inspect(e)}")
      end
    end)
    :ok
  end

  defp export_to_target(state, {:file, path}) do
    metrics = export_json(state.counters, state.gauges, state.histograms)
    try do
      File.write!(path, metrics <> "\n", [:append])
    rescue
      e -> Logger.warning("File export failed: #{inspect(e)}")
    end
  end

  defp export_to_target(state, {:influxdb, url, database}) do
    metrics = export_influxdb(state.counters, state.gauges, state.histograms)
    Task.start(fn ->
      try do
        Req.post(url <> "/write?db=#{database}", body: metrics)
      rescue
        e -> Logger.warning("InfluxDB export failed: #{inspect(e)}")
      end
    end)
    :ok
  end

  defp export_to_target(state, target) do
    Logger.warning("Unknown export target: #{inspect(target)}")
    :ok
  end
end
