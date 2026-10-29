defmodule ElixirServer.ConnectionPool do
  use GenServer
  require Logger

  @default_host "localhost"
  @default_port 50051
  @default_pool_size 5
  @health_check_interval 30_000  # 30 секунд
  @reconnect_delay 5_000  # 5 секунд

  # ========== Client API ==========

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_connection(service_name \\ "go") do
    GenServer.call(__MODULE__, {:get_connection, service_name})
  end

  def send_command(service_name, command, params) do
    GenServer.call(__MODULE__, {:send_command, service_name, command, params}, 10_000)
  end

  def get_service_status(service_name) do
    GenServer.call(__MODULE__, {:get_status, service_name})
  end

  def get_all_statuses do
    GenServer.call(__MODULE__, :get_all_statuses)
  end

  # ========== Server Callbacks ==========

  def init(opts) do
    services = [
      %{
        name: "go",
        host: Application.get_env(:elixir_server, :go_service_host, @default_host),
        port: Application.get_env(:elixir_server, :go_service_port, @default_port),
        pool_size: @default_pool_size,
        status: :disconnected,
        last_heartbeat: nil,
        latency_ms: 0,
        connections: [],
        reconnect_timer: nil
      },
      %{
        name: "python",
        host: Application.get_env(:elixir_server, :python_service_host, "localhost"),
        port: Application.get_env(:elixir_server, :python_service_port, 50052),
        pool_size: @default_pool_size,
        status: :disconnected,
        last_heartbeat: nil,
        latency_ms: 0,
        connections: [],
        reconnect_timer: nil
      },
      %{
        name: "audio",
        host: Application.get_env(:elixir_server, :audio_service_host, "localhost"),
        port: Application.get_env(:elixir_server, :audio_service_port, 50053),
        pool_size: @default_pool_size,
        status: :disconnected,
        last_heartbeat: nil,
        latency_ms: 0,
        connections: [],
        reconnect_timer: nil
      }
    ]

    state = %{
      services: Enum.into(services, %{}, fn s -> {s.name, s} end),
      metrics: %{
        total_commands_sent: 0,
        total_commands_failed: 0,
        total_heartbeats: 0,
        last_error: nil,
        error_counters: %{}
      }
    }

    # Запускаем health check
    schedule_health_check()

    # Инициализируем соединения
    Enum.each(services, fn service ->
      connect_service(service.name, state)
    end)

    {:ok, state}
  end

  def handle_call({:get_connection, service_name}, _from, state) do
    case get_service_connection(state, service_name) do
      {:ok, channel} ->
        {:reply, {:ok, channel}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:send_command, service_name, command, params}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    case send_command_to_service(service_name, command, params, state) do
      {:ok, response} ->
        latency = System.monotonic_time(:millisecond) - start_time

        # Обновляем метрики
        metrics = update_success_metrics(state.metrics, service_name, command, latency)

        # Обновляем статус сервиса
        state = update_service_status(state, service_name, :healthy, latency)

        Logger.debug("✅ Command #{command} sent to #{service_name} in #{latency}ms")
        {:reply, {:ok, response}, %{state | metrics: metrics}}

      {:error, reason} ->
        # Обновляем метрики ошибок
        metrics = update_error_metrics(state.metrics, service_name, command, reason)

        # Помечаем сервис как недоступный
        state = update_service_status(state, service_name, :unhealthy, nil, reason)

        Logger.error("❌ Failed to send command #{command} to #{service_name}: #{reason}")
        {:reply, {:error, reason}, %{state | metrics: metrics}}
    end
  end

  def handle_call({:get_status, service_name}, _from, state) do
    service = Map.get(state.services, service_name)
    status = if service do
      %{
        name: service.name,
        status: service.status,
        last_heartbeat: service.last_heartbeat,
        latency_ms: service.latency_ms,
        error_message: service.error_message
      }
    else
      %{error: "Service not found"}
    end
    {:reply, status, state}
  end

  def handle_call(:get_all_statuses, _from, state) do
    statuses = Enum.map(state.services, fn {name, service} ->
      {name, %{
        name: name,
        status: service.status,
        last_heartbeat: service.last_heartbeat,
        latency_ms: service.latency_ms,
        pool_size: length(service.connections),
        error_message: service.error_message
      }}
    end) |> Map.new()

    {:reply, statuses, state}
  end

  def handle_info(:health_check, state) do
    state = perform_health_checks(state)
    schedule_health_check()
    {:noreply, state}
  end

  def handle_info({:reconnect, service_name}, state) do
    state = connect_service(service_name, state)
    {:noreply, state}
  end

  def handle_info({:GRPC_Client, :closed, channel}, state) do
    # Канал закрыт, удаляем его из пула
    state = remove_closed_connection(state, channel)
    {:noreply, state}
  end

  # ========== Внутренние функции ==========

  defp get_service_connection(state, service_name) do
    case Map.get(state.services, service_name) do
      nil ->
        {:error, "Service #{service_name} not found"}

      service ->
        case List.pop_at(service.connections, 0) do
          {nil, _} ->
            {:error, "No available connections for #{service_name}"}
          {channel, remaining} ->
            # Обновляем пул
            updated_service = %{service | connections: remaining}
            state = put_in(state.services[service_name], updated_service)

            # Возвращаем канал и функцию для возврата
            {:ok, channel, fn -> return_connection(service_name, channel) end}
        end
    end
  end

  defp return_connection(service_name, channel) do
    GenServer.cast(__MODULE__, {:return_connection, service_name, channel})
  end

  def handle_cast({:return_connection, service_name, channel}, state) do
    case Map.get(state.services, service_name) do
      nil ->
        # Сервис не найден, закрываем канал
        :grpc_client.close(channel)
        {:noreply, state}

      service ->
        # Возвращаем канал в пул
        updated_service = %{service | connections: [channel | service.connections]}
        state = put_in(state.services[service_name], updated_service)
        {:noreply, state}
    end
  end

  defp connect_service(service_name, state) do
    service = Map.get(state.services, service_name)

    if is_nil(service) do
      state
    else
      Logger.info("🔌 Connecting to #{service_name} service at #{service.host}:#{service.port}")

      connections = Enum.map(1..service.pool_size, fn _ ->
        case :grpc_client.connect(to_charlist(service.host), service.port) do
          {:ok, channel} ->
            channel
          {:error, reason} ->
            Logger.error("❌ Failed to connect to #{service_name}: #{reason}")
            nil
        end
      end)
      |> Enum.filter(&(&1 != nil))

      updated_service = %{service |
        connections: connections,
        status: if length(connections) > 0 do :healthy else :disconnected end,
        error_message: if length(connections) == 0 do "Failed to connect" else nil end
      }

      if length(connections) > 0 do
        Logger.info("✅ Connected to #{service_name} with #{length(connections)} connections")
      else
        schedule_reconnect(service_name)
      end

      put_in(state.services[service_name], updated_service)
    end
  end

  defp send_command_to_service(service_name, command, params, state) do
    case get_service_connection(state, service_name) do
      {:ok, channel, return_fn} ->
        try do
          # Создаём gRPC запрос
          request = %GoService.V1.CommandRequest{
            command: command,
            service: "elixir_gateway",
            params: Map.new(params, fn {k, v} -> {k, to_string(v)} end),
            timestamp: :os.system_time(:seconds),
            source: "elixir_gateway"
          }

          # Отправляем запрос
          case GoService.V1.GoService.Stub.execute_command(channel, request, timeout: 5000) do
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
    Enum.reduce(state.services, state, fn {name, service}, acc ->
      if service.status == :healthy do
        case check_service_health(name, service, acc) do
          {:ok, latency} ->
            update_service_status(acc, name, :healthy, latency)
          {:error, reason} ->
            Logger.warning("⚠️ Health check failed for #{name}: #{reason}")
            update_service_status(acc, name, :unhealthy, nil, reason)
        end
      else
        acc
      end
    end)
  end

  defp check_service_health(service_name, service, state) do
    case get_service_connection(state, service_name) do
      {:ok, channel, return_fn} ->
        start_time = System.monotonic_time(:millisecond)

        request = %GoService.V1.HealthRequest{
          service: "elixir_gateway"
        }

        result = case GoService.V1.GoService.Stub.health_check(channel, request, timeout: 2000) do
          {:ok, response} ->
            latency = System.monotonic_time(:millisecond) - start_time
            return_fn.()
            {:ok, latency}
          {:error, error} ->
            return_fn.()
            {:error, error}
        end

        result

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_service_status(state, service_name, status, latency \\ nil, error_message \\ nil) do
    update_in(state.services[service_name], fn service ->
      service
      |> Map.put(:status, status)
      |> Map.put(:last_heartbeat, if status == :healthy, do: :os.system_time(:seconds), else: service.last_heartbeat)
      |> Map.put(:latency_ms, latency || service.latency_ms)
      |> Map.put(:error_message, error_message)
    end)
  end

  defp update_success_metrics(metrics, service_name, command, latency) do
    %{
      metrics |
      total_commands_sent: metrics.total_commands_sent + 1,
      total_heartbeats: metrics.total_heartbeats + 1
    }
  end

  defp update_error_metrics(metrics, service_name, command, reason) do
    error_key = "#{service_name}:#{command}"
    error_counters = Map.update(metrics.error_counters, error_key, 1, &(&1 + 1))

    %{
      metrics |
      total_commands_failed: metrics.total_commands_failed + 1,
      error_counters: error_counters,
      last_error: %{
        service: service_name,
        command: command,
        reason: reason,
        timestamp: :os.system_time(:seconds)
      }
    }
  end

  defp remove_closed_connection(state, closed_channel) do
    Enum.reduce(state.services, state, fn {name, service}, acc ->
      connections = Enum.filter(service.connections, fn ch ->
        ch != closed_channel
      end)

      if length(connections) < length(service.connections) do
        Logger.warning("🔌 Removed closed connection from #{name} pool")
        updated_service = %{service | connections: connections}
        put_in(acc.services[name], updated_service)
      else
        acc
      end
    end)
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp schedule_reconnect(service_name) do
    Process.send_after(self(), {:reconnect, service_name}, @reconnect_delay)
  end

  # ========== Метрики для Prometheus ==========

  def get_metrics do
    state = :persistent_term.get({__MODULE__, :state}, %{})

    {Enum.map(state.services, fn {name, service} ->
      "elixir_grpc_connections_total{service=\"#{name}\"} #{length(service.connections)}"
    end) |> Enum.join("\n")}

    {Enum.map(state.services, fn {name, service} ->
      status = if service.status == :healthy, do: 1, else: 0
      "elixir_grpc_service_status{service=\"#{name}\"} #{status}"
    end) |> Enum.join("\n")}

    {Enum.map(state.services, fn {name, service} ->
      "elixir_grpc_latency_ms{service=\"#{name}\"} #{service.latency_ms || 0}"
    end) |> Enum.join("\n")}

    elixir_grpc_commands_total {state.metrics[:total_commands_sent] || 0}

    elixir_grpc_commands_failed {state.metrics[:total_commands_failed] || 0}
  end
end
