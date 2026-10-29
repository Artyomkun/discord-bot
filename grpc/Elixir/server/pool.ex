defmodule ElixirServer.Pool do
  use GenServer
  require Logger

  @default_host "localhost"
  @default_port 50051
  @pool_size 3
  @health_check_interval 30_000
  @reconnect_delay 5_000
  @command_timeout 10_000

  # ========== Client API ==========

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_channel(service \\ :go) do
    GenServer.call(__MODULE__, {:get_channel, service})
  end

  def send_command(service, command, params) do
    GenServer.call(__MODULE__, {:send_command, service, command, params}, @command_timeout)
  end

  def get_status(service) do
    GenServer.call(__MODULE__, {:get_status, service})
  end

  def get_all_statuses do
    GenServer.call(__MODULE__, :get_all_statuses)
  end

  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  # ========== Server Callbacks ==========

  def init(opts) do
    services_config = [
      go: %{
        host: Application.get_env(:elixir_server, :go_service_host, @default_host),
        port: Application.get_env(:elixir_server, :go_service_port, @default_port),
        pool_size: @pool_size,
        module: GoService.V1.GoService.Stub
      },
      python: %{
        host: Application.get_env(:elixir_server, :python_service_host, "localhost"),
        port: Application.get_env(:elixir_server, :python_service_port, 50052),
        pool_size: @pool_size,
        module: PythonService.V1.PythonService.Stub
      },
      audio: %{
        host: Application.get_env(:elixir_server, :audio_service_host, "localhost"),
        port: Application.get_env(:elixir_server, :audio_service_port, 50053),
        pool_size: @pool_size,
        module: AudioService.V1.AudioService.Stub
      }
    ]

    state = %{
      pools: %{},
      metrics: %{
        commands_sent: 0,
        commands_succeeded: 0,
        commands_failed: 0,
        errors_by_service: %{},
        errors_by_command: %{},
        latencies: %{}
      },
      config: services_config
    }

    # Инициализируем пулы
    state = Enum.reduce(services_config, state, fn {service, config}, acc ->
      create_pool(acc, service, config)
    end)

    # Запускаем health check
    schedule_health_check()

    {:ok, state}
  end

  def handle_call({:get_channel, service}, _from, state) do
    case get_available_channel(state, service) do
      {:ok, channel, return_fn} ->
        {:reply, {:ok, channel, return_fn}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_command, service, command, params}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    case send_command_to_service(state, service, command, params) do
      {:ok, response} ->
        latency = System.monotonic_time(:millisecond) - start_time

        # Обновляем метрики успеха
        state = update_success_metrics(state, service, command, latency)

        Logger.debug("✅ Command #{command} sent to #{service} in #{latency}ms")
        {:reply, {:ok, response}, state}

      {:error, reason} ->
        # Обновляем метрики ошибок
        state = update_error_metrics(state, service, command, reason)

        Logger.error("❌ Failed to send command #{command} to #{service}: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_status, service}, _from, state) do
    status = case Map.get(state.pools, service) do
      nil -> %{status: :not_found, error: "Service not found"}
      pool -> %{
        status: pool.status,
        healthy_connections: length(pool.available),
        total_connections: pool.pool_size,
        last_heartbeat: pool.last_heartbeat,
        latency_ms: pool.latency_ms,
        error_message: pool.error_message
      }
    end
    {:reply, status, state}
  end

  def handle_call(:get_all_statuses, _from, state) do
    statuses = Enum.map(state.pools, fn {service, pool} ->
      {service, %{
        status: pool.status,
        connections: length(pool.available),
        pool_size: pool.pool_size,
        last_heartbeat: pool.last_heartbeat,
        latency_ms: pool.latency_ms
      }}
    end) |> Map.new()

    {:reply, statuses, state}
  end

  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  def handle_info(:health_check, state) do
    state = perform_health_checks(state)
    schedule_health_check()
    {:noreply, state}
  end

  def handle_info({:reconnect, service}, state) do
    state = reconnect_service(state, service)
    {:noreply, state}
  end

  def handle_info({:GRPC_Client, :closed, channel}, state) do
    state = remove_closed_channel(state, channel)
    {:noreply, state}
  end

  def handle_cast({:return_channel, service, channel}, state) do
    state = return_channel_to_pool(state, service, channel)
    {:noreply, state}
  end

  # ========== Внутренние функции ==========

  defp create_pool(state, service, config) do
    Logger.info("🔌 Creating pool for #{service} at #{config.host}:#{config.port}")

    channels = Enum.map(1..config.pool_size, fn _ ->
      case :grpc_client.connect(to_charlist(config.host), config.port) do
        {:ok, channel} -> channel
        {:error, reason} ->
          Logger.error("❌ Failed to connect to #{service}: #{reason}")
          nil
      end
    end)
    |> Enum.filter(&(&1 != nil))

    pool = %{
      host: config.host,
      port: config.port,
      pool_size: config.pool_size,
      module: config.module,
      available: channels,
      in_use: [],
      status: if length(channels) > 0 do :healthy else :disconnected end,
      last_heartbeat: nil,
      latency_ms: 0,
      error_message: nil,
      reconnect_timer: nil
    }

    if length(channels) == 0 do
      schedule_reconnect(service)
    end

    put_in(state.pools[service], pool)
  end

  defp get_available_channel(state, service) do
    case Map.get(state.pools, service) do
      nil ->
        {:error, "Service #{service} not found"}

      pool ->
        case List.pop_at(pool.available, 0) do
          {nil, _} ->
            {:error, "No available channels for #{service}"}

          {channel, remaining} ->
            # Обновляем пул
            updated_pool = %{pool |
              available: remaining,
              in_use: [channel | pool.in_use]
            }
            state = put_in(state.pools[service], updated_pool)

            # Возвращаем канал и функцию возврата
            return_fn = fn ->
              GenServer.cast(__MODULE__, {:return_channel, service, channel})
            end

            {:ok, channel, return_fn}
        end
    end
  end

  defp return_channel_to_pool(state, service, channel) do
    case Map.get(state.pools, service) do
      nil ->
        :grpc_client.close(channel)
        state

      pool ->
        # Удаляем из in_use и добавляем в available
        in_use = List.delete(pool.in_use, channel)
        available = [channel | pool.available]

        updated_pool = %{pool | in_use: in_use, available: available}
        put_in(state.pools[service], updated_pool)
    end
  end

  defp send_command_to_service(state, service, command, params) do
    case get_available_channel(state, service) do
      {:ok, channel, return_fn} ->
        try do
          # Создаём запрос в зависимости от сервиса
          request = case service do
            :go ->
              %GoService.V1.CommandRequest{
                command: command,
                service: "elixir_gateway",
                params: Map.new(params, fn {k, v} -> {k, to_string(v)} end),
                timestamp: :os.system_time(:seconds),
                source: "elixir_gateway"
              }

            :python ->
              %PythonService.V1.CommandRequest{
                command: command,
                service: "elixir_gateway",
                params: Map.new(params, fn {k, v} -> {k, to_string(v)} end),
                timestamp: :os.system_time(:seconds)
              }

            :audio ->
              %AudioService.V1.AudioRequest{
                command: command,
                params: Map.new(params, fn {k, v} -> {k, to_string(v)} end),
                timestamp: :os.system_time(:seconds)
              }
          end

          # Получаем модуль для вызова
          module = Map.get(state.pools, service).module

          # Отправляем запрос
          case module.execute_command(channel, request, timeout: @command_timeout) do
            {:ok, response} ->
              return_fn.()
              {:ok, response}

            {:error, error} ->
              return_fn.()
              {:error, error}
          end
        catch
          :exit, reason ->
            return_fn.()
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_health_checks(state) do
    Enum.reduce(state.pools, state, fn {service, pool}, acc ->
      if pool.status == :healthy do
        case check_service_health(acc, service, pool) do
          {:ok, latency} ->
            update_pool_status(acc, service, :healthy, latency)
          {:error, reason} ->
            Logger.warning("⚠️ Health check failed for #{service}: #{reason}")
            update_pool_status(acc, service, :unhealthy, nil, reason)
        end
      else
        acc
      end
    end)
  end

  defp check_service_health(state, service, pool) do
    case get_available_channel(state, service) do
      {:ok, channel, return_fn} ->
        start_time = System.monotonic_time(:millisecond)

        result = case service do
          :go ->
            request = %GoService.V1.HealthRequest{service: "elixir_gateway"}

            case pool.module.health_check(channel, request, timeout: 2000) do
              {:ok, _response} ->
                latency = System.monotonic_time(:millisecond) - start_time
                return_fn.()
                {:ok, latency}
              {:error, error} ->
                return_fn.()
                {:error, error}
            end

          _ ->
            # Для других сервисов просто проверяем соединение
            return_fn.()
            {:ok, 0}
        end

        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_pool_status(state, service, status, latency \\ nil, error_message \\ nil) do
    update_in(state.pools[service], fn pool ->
      pool
      |> Map.put(:status, status)
      |> Map.put(:last_heartbeat, if status == :healthy, do: :os.system_time(:seconds), else: pool.last_heartbeat)
      |> Map.put(:latency_ms, latency || pool.latency_ms)
      |> Map.put(:error_message, error_message)
    end)
  end

  defp reconnect_service(state, service) do
    case Map.get(state.pools, service) do
      nil ->
        state

      pool ->
        Logger.info("🔄 Reconnecting to #{service}")

        # Создаём новые соединения
        new_channels = Enum.map(1..pool.pool_size, fn _ ->
          case :grpc_client.connect(to_charlist(pool.host), pool.port) do
            {:ok, channel} -> channel
            {:error, reason} ->
              Logger.error("❌ Failed to reconnect to #{service}: #{reason}")
              nil
          end
        end)
        |> Enum.filter(&(&1 != nil))

        # Закрываем старые каналы
        Enum.each(pool.available ++ pool.in_use, fn ch ->
          :grpc_client.close(ch)
        end)

        updated_pool = %{pool |
          available: new_channels,
          in_use: [],
          status: if length(new_channels) > 0 do :healthy else :disconnected end,
          error_message: if length(new_channels) == 0 do "Reconnection failed" else nil end
        }

        if length(new_channels) == 0 do
          schedule_reconnect(service)
        end

        put_in(state.pools[service], updated_pool)
    end
  end

  defp remove_closed_channel(state, closed_channel) do
    Enum.reduce(state.pools, state, fn {service, pool}, acc ->
      # Удаляем из available
      available = Enum.filter(pool.available, fn ch -> ch != closed_channel end)
      in_use = Enum.filter(pool.in_use, fn ch -> ch != closed_channel end)

      if length(available) < length(pool.available) or length(in_use) < length(pool.in_use) do
        Logger.warning("🔌 Removed closed channel from #{service} pool")

        updated_pool = %{pool | available: available, in_use: in_use}
        acc = put_in(acc.pools[service], updated_pool)

        # Если нет доступных каналов, переподключаемся
        if length(available) == 0 and length(in_use) == 0 do
          schedule_reconnect(service)
        end

        acc
      else
        acc
      end
    end)
  end

  defp update_success_metrics(state, service, command, latency) do
    metrics = state.metrics

    # Обновляем латентность
    latencies = Map.update(metrics.latencies, service, [latency], fn list ->
      [latency | list] |> Enum.take(100)
    end)

    %{state | metrics: %{
      metrics |
      commands_sent: metrics.commands_sent + 1,
      commands_succeeded: metrics.commands_succeeded + 1,
      latencies: latencies
    }}
  end

  defp update_error_metrics(state, service, command, reason) do
    metrics = state.metrics

    # Обновляем счётчики ошибок по сервису
    errors_by_service = Map.update(metrics.errors_by_service, service, 1, &(&1 + 1))

    # Обновляем счётчики ошибок по команде
    error_key = "#{service}:#{command}"
    errors_by_command = Map.update(metrics.errors_by_command, error_key, 1, &(&1 + 1))

    %{state | metrics: %{
      metrics |
      commands_sent: metrics.commands_sent + 1,
      commands_failed: metrics.commands_failed + 1,
      errors_by_service: errors_by_service,
      errors_by_command: errors_by_command
    }}
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp schedule_reconnect(service) do
    Process.send_after(self(), {:reconnect, service}, @reconnect_delay)
  end

  # ========== Метрики для Prometheus ==========

  def format_prometheus_metrics do
    state = :persistent_term.get({__MODULE__, :state}, %{})
    metrics = state.metrics || %{}

    {Enum.map(state.pools, fn {service, pool} ->
      "elixir_pool_connections_total{service=\"#{service}\"} #{length(pool.available)}"
    end) |> Enum.join("\n")}

    {Enum.map(state.pools, fn {service, pool} ->
      status = if pool.status == :healthy, do: 1, else: 0
      "elixir_pool_service_status{service=\"#{service}\"} #{status}"
    end) |> Enum.join("\n")}

    {Enum.map(state.pools, fn {service, pool} ->
      avg_latency = if pool.latency_ms > 0 do
        pool.latency_ms
      else
        case Map.get(metrics.latencies, service, []) do
          [] -> 0
          list -> round(Enum.sum(list) / length(list))
        end
      end
      "elixir_pool_latency_ms{service=\"#{service}\"} #{avg_latency}"
    end) |> Enum.join("\n")}

    elixir_pool_commands_total {metrics.commands_sent || 0}

    elixir_pool_commands_succeeded {metrics.commands_succeeded || 0}

    elixir_pool_commands_failed {metrics.commands_failed || 0}
rs by service
    # TYPE elixir_pool_errors_total counter
    {Enum.map(metrics.errors_by_service || %{}, fn {service, count} ->
      "elixir_pool_errors_total{service=\"#{service}\"} #{count}"
    end) |> Enum.join("\n")}
  end
end
