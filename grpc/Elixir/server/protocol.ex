defmodule ElixirServer.Protocol do
  use ElixirServer.Server, service: ElixirServer.V1.ElixirService.Service

  require Logger

  # Состояние сервера
  defstruct [
    :unresolved_tasks,
    :error_records,
    :service_statuses,
    :thresholds,
    :command_queue,
    :go_channel
  ]

  # Инициализация
  def init(_) do
    Logger.info("🚀 Elixir gRPC Server starting...")

    # Запускаем пул соединений с Go сервисом
    start_go_connection_pool()

    state = %__MODULE__{
      unresolved_tasks: %{},
      error_records: [],
      service_statuses: %{
        "go" => %{status: "unknown", last_heartbeat: nil, latency_ms: 0},
        "python" => %{status: "unknown", last_heartbeat: nil, latency_ms: 0},
        "audio" => %{status: "unknown", last_heartbeat: nil, latency_ms: 0},
        "gateway" => %{status: "unknown", last_heartbeat: nil, latency_ms: 0}
      },
      thresholds: %{
        error_rate_warning: 0.05,
        error_rate_critical: 0.1,
        unresolved_alert_threshold: 3,
        consecutive_errors: 5,
        time_window_seconds: 60
      },
      command_queue: [],
      go_channel: nil
    }

    # Запускаем фоновую обработку метрик
    start_metrics_processor()

    {:ok, state}
  end

  # ========== gRPC Handlers ==========

  # Обработка команды от Python Core
  def execute_command(request, stream) do
    Logger.info("📨 Received command: #{request.command} from user #{request.user_id}")

    start_time = System.monotonic_time(:millisecond)

    # Маршрутизация команды
    response = case request.command do
      "play" -> handle_play_command(request)
      "stop" -> handle_stop_command(request)
      "skip" -> handle_skip_command(request)
      "status" -> handle_status_command(request)
      "metrics" -> handle_metrics_command(request)
      "health" -> handle_health_command(request)
      _ -> %ElixirServer.V1.CommandResponse{
        success: false,
        message: "Unknown command: #{request.command}"
      }
    end

    latency = System.monotonic_time(:millisecond) - start_time

    # Записываем метрику команды
    record_command_metrics(request.command, response.success, latency, request.user_id)

    # Возвращаем ответ с задержкой
    %{response | latency_ms: latency}
  end

  # Получение статуса всех сервисов
  def get_all_services_status(_request, _stream) do
    state = get_current_state()

    %ElixirServer.V1.AllServicesStatusResponse{
      success: true,
      go: %ElixirServer.V1.ServiceStatus{
        name: "Go Service",
        status: get_service_status(state, "go"),
        message: get_service_message(state, "go"),
        last_heartbeat: get_last_heartbeat(state, "go"),
        latency_ms: get_service_latency(state, "go")
      },
      python: %ElixirServer.V1.ServiceStatus{
        name: "Python Core",
        status: get_service_status(state, "python"),
        message: get_service_message(state, "python"),
        last_heartbeat: get_last_heartbeat(state, "python"),
        latency_ms: get_service_latency(state, "python")
      },
      audio: %ElixirServer.V1.ServiceStatus{
        name: "Audio Service",
        status: get_service_status(state, "audio"),
        message: get_service_message(state, "audio"),
        last_heartbeat: get_last_heartbeat(state, "audio"),
        latency_ms: get_service_latency(state, "audio")
      },
      gateway: %ElixirServer.V1.ServiceStatus{
        name: "Java Gateway",
        status: get_service_status(state, "gateway"),
        message: get_service_message(state, "gateway"),
        last_heartbeat: get_last_heartbeat(state, "gateway"),
        latency_ms: get_service_latency(state, "gateway")
      }
    }
  end

  # Health check
  def health_check(request, _stream) do
    Logger.debug("🔍 Health check from service: #{request.service}")

    # Обновляем статус сервиса
    if request.service != "" do
      update_service_heartbeat(request.service)
    end

    state = get_current_state()

    %ElixirServer.V1.HealthResponse{
      status: "healthy",
      message: "Elixir Gateway is running",
      timestamp: :os.system_time(:seconds),
      services: Enum.map(state.service_statuses, fn {name, status} ->
        {name, %ElixirServer.V1.ServiceStatus{
          name: name,
          status: status.status,
          message: status.message,
          last_heartbeat: status.last_heartbeat || 0,
          latency_ms: status.latency_ms || 0
        }}
      end) |> Map.new()
    }
  end

  # ========== Обработка команд ==========

  defp handle_play_command(request) do
    params = Map.new(request.params, fn {k, v} -> {k, v} end)
    url = Map.get(params, "url")

    if url do
      # Отправляем в Go сервис через gRPC
      case send_to_go_service("play", %{
        "guild_id" => request.guild_id,
        "channel_id" => request.channel_id,
        "url" => url,
        "user_id" => request.user_id
      }) do
        {:ok, response} ->
          %ElixirServer.V1.CommandResponse{
            success: response.success,
            message: response.message,
            data: response.data
          }
        {:error, error} ->
          %ElixirServer.V1.CommandResponse{
            success: false,
            message: "Failed to send to Go service: #{error}"
          }
      end
    else
      %ElixirServer.V1.CommandResponse{
        success: false,
        message: "No URL provided"
      }
    end
  end

  defp handle_stop_command(request) do
    case send_to_go_service("stop", %{"guild_id" => request.guild_id}) do
      {:ok, response} ->
        %ElixirServer.V1.CommandResponse{
          success: response.success,
          message: response.message
        }
      {:error, error} ->
        %ElixirServer.V1.CommandResponse{
          success: false,
          message: "Failed to stop: #{error}"
        }
    end
  end

  defp handle_skip_command(request) do
    case send_to_go_service("skip", %{"guild_id" => request.guild_id}) do
      {:ok, response} ->
        %ElixirServer.V1.CommandResponse{
          success: response.success,
          message: response.message
        }
      {:error, error} ->
        %ElixirServer.V1.CommandResponse{
          success: false,
          message: "Failed to skip: #{error}"
        }
    end
  end

  defp handle_status_command(_request) do
    state = get_current_state()
    status = Map.get(state.service_statuses, "audio", %{})

    %ElixirServer.V1.CommandResponse{
      success: true,
      message: "Audio service is #{status.status}",
      data: %{
        "status" => status.status,
        "latency_ms" => to_string(status.latency_ms),
        "last_heartbeat" => to_string(status.last_heartbeat || 0)
      }
    }
  end

  defp handle_metrics_command(_request) do
    state = get_current_state()

    %ElixirServer.V1.CommandResponse{
      success: true,
      message: "Metrics collected",
      data: %{
        "total_errors" => to_string(length(state.error_records)),
        "unresolved_tasks" => to_string(map_size(state.unresolved_tasks)),
        "pending_commands" => to_string(length(state.command_queue)),
        "go_status" => get_service_status(state, "go"),
        "python_status" => get_service_status(state, "python"),
        "audio_status" => get_service_status(state, "audio")
      }
    }
  end

  defp handle_health_command(_request) do
    %ElixirServer.V1.CommandResponse{
      success: true,
      message: "Elixir Gateway is healthy",
      data: %{
        "status" => "healthy",
        "timestamp" => to_string(:os.system_time(:seconds))
      }
    }
  end

  # ========== Отправка в Go сервис через gRPC ==========

  defp send_to_go_service(command, params) do
    case get_go_channel() do
      {:ok, channel} ->
        request = %GoService.V1.CommandRequest{
          command: command,
          service: "elixir_gateway",
          params: Map.new(params, fn {k, v} -> {k, to_string(v)} end),
          timestamp: :os.system_time(:seconds),
          source: "elixir_gateway"
        }

        case GoService.V1.GoService.Stub.execute_command(channel, request, timeout: 5000) do
          {:ok, response} ->
            Logger.info("✅ Command #{command} sent to Go service")
            {:ok, response}

          {:error, %GRPC.RPCError{status: status, message: message}} ->
            Logger.error("❌ gRPC error: #{status} - #{message}")
            {:error, message}
        end

      {:error, reason} ->
        Logger.error("❌ No connection to Go service: #{reason}")
        {:error, reason}
    end
  end

  # Получение gRPC канала к Go сервису
  defp get_go_channel do
    case :persistent_term.get(:go_grpc_channel, nil) do
      nil ->
        host = Application.get_env(:elixir_server, :go_service_host, "localhost")
        port = Application.get_env(:elixir_server, :go_service_port, 50051)

        case :grpc_client.connect(to_charlist(host), port) do
          {:ok, channel} ->
            :persistent_term.put(:go_grpc_channel, channel)
            Logger.info("✅ Connected to Go gRPC service at #{host}:#{port}")
            {:ok, channel}

          {:error, reason} ->
            Logger.error("❌ Failed to connect to Go service: #{reason}")
            {:error, reason}
        end

      channel ->
        {:ok, channel}
    end
  end

  # ========== Приём метрик от Go/Java сервисов ==========

  # HTTP эндпоинт для приёма нерешённых задач (вызывается из Go/Java)
  def handle_unresolved_task(service, task_data) do
    Logger.warning("📥 Unresolved task from #{service}: #{task_data["error"]}")

    task = %{
      task_id: task_data["task_id"],
      error_type: task_data["error_type"],
      error: task_data["error"],
      method: task_data["method"],
      client_id: task_data["client_id"],
      service: service,
      timestamp: :os.system_time(:seconds),
      retry_count: task_data["retry_count"],
      status: "pending"
    }

    update_state(fn state ->
      unresolved_tasks = Map.put(state.unresolved_tasks, task.task_id, task)

      # Добавляем запись об ошибке
      error_record = %{
        timestamp: :os.system_time(:seconds),
        error_type: "unresolved",
        method: task.method,
        error: task.error,
        client_id: task.client_id,
        service: service,
        resolution: nil,
        resolved: false
      }

      error_records = [error_record | state.error_records] |> Enum.take(10000)

      # Принимаем решение
      resolution = decide_resolution(error_record, state.thresholds)

      # Отправляем команду сервису
      command = send_command_to_service(service, resolution, task.task_id)

      command_queue = [command | state.command_queue]

      %{state |
        unresolved_tasks: unresolved_tasks,
        error_records: error_records,
        command_queue: command_queue
      }
    end)
  end

  # HTTP эндпоинт для приёма критических алертов
  def handle_critical_alert(service, alert_data) do
    Logger.critical("🔴 Critical alert from #{service}: #{inspect(alert_data)}")

    update_state(fn state ->
      error_record = %{
        timestamp: :os.system_time(:seconds),
        error_type: "critical",
        method: "critical_alert",
        error: "Critical alert: #{alert_data["error_count"]} errors",
        client_id: alert_data["client_id"],
        service: service,
        resolution: "escalate",
        resolved: false
      }

      error_records = [error_record | state.error_records]

      Logger.critical("🚨 ESCALATION: Critical error from #{service}")

      %{state | error_records: error_records}
    end)
  end

  # ========== Принятие решений ==========

  defp decide_resolution(error_record, thresholds) do
    error_msg = String.downcase(error_record.error)

    cond do
      String.contains?(error_msg, "timeout") -> "increase_timeout"
      String.contains?(error_msg, "connection refused") -> "retry"
      String.contains?(error_msg, "connection reset") -> "retry"
      String.contains?(error_msg, "memory") -> "restart"
      String.contains?(error_msg, "out of memory") -> "restart"
      String.contains?(error_msg, "rate limit") -> "alert"
      error_record.error_type == "unresolved" -> "escalate"
      true -> "ignore"
    end
  end

  defp send_command_to_service(service, resolution, task_id) do
    command_map = %{
      "increase_timeout" => "increase_timeout",
      "retry" => "increase_retry",
      "restart" => "reconnect",
      "escalate" => "report_status"
    }

    command = Map.get(command_map, resolution, "report_status")

    %{
      target_service: service,
      command: command,
      params: %{
        "task_id" => task_id,
        "resolution" => resolution,
        "reason" => "unresolved_task"
      },
      timestamp: :os.system_time(:seconds)
    }
  end

  # ========== Вспомогательные функции ==========

  defp record_command_metrics(command, success, latency, user_id) do
    Logger.debug("📊 Command metrics: #{command} success=#{success} latency=#{latency}ms user=#{user_id}")
  end

  defp update_service_heartbeat(service) do
    update_state(fn state ->
      statuses = Map.update!(state.service_statuses, service, fn status ->
        Map.merge(status, %{
          last_heartbeat: :os.system_time(:seconds),
          status: "healthy",
          latency_ms: status.latency_ms || 0
        })
      end)

      %{state | service_statuses: statuses}
    end)
  end

  defp get_service_status(state, service) do
    get_in(state, [:service_statuses, service, :status]) || "unknown"
  end

  defp get_service_message(state, service) do
    get_in(state, [:service_statuses, service, :message]) || ""
  end

  defp get_last_heartbeat(state, service) do
    get_in(state, [:service_statuses, service, :last_heartbeat]) || 0
  end

  defp get_service_latency(state, service) do
    get_in(state, [:service_statuses, service, :latency_ms]) || 0
  end

  defp get_current_state do
    :persistent_term.get(:elixir_metrics_state, %__MODULE__{})
  end

  defp update_state(fun) do
    current = get_current_state()
    {new_state, result} = fun.(current)
    :persistent_term.put(:elixir_metrics_state, new_state)
    result
  end

  defp start_go_connection_pool do
    # Запускаем в фоне поддержание соединения
    spawn(fn ->
      Process.sleep(1000)
      get_go_channel()
    end)
  end

  defp start_metrics_processor do
    spawn(fn ->
      process_metrics_loop()
    end)
  end

  defp process_metrics_loop do
    Process.sleep(5000)

    state = get_current_state()

    # Проверяем health сервисов
    check_services_health(state)

    # Проверяем нерешённые задачи
    check_unresolved_tasks(state)

    process_metrics_loop()
  end

  defp check_services_health(state) do
    now = :os.system_time(:seconds)

    Enum.each(state.service_statuses, fn {service, status} ->
      last_heartbeat = status.last_heartbeat || 0

      if now - last_heartbeat > 30 and last_heartbeat > 0 do
        Logger.warning("⚠️ Service #{service} heartbeat timeout")

        update_state(fn s ->
          statuses = Map.update!(s.service_statuses, service, fn st ->
            Map.merge(st, %{status: "unhealthy", message: "No heartbeat for 30 seconds"})
          end)
          %{s | service_statuses: statuses}
        end)
      end
    end)
  end

  defp check_unresolved_tasks(state) do
    now = :os.system_time(:seconds)

    Enum.each(state.unresolved_tasks, fn {task_id, task} ->
      if now - task.timestamp > 3600 and task.status == "pending" do
        Logger.critical("🚨 Unresolved task #{task_id} expired after 1 hour")

        # Эскалируем
        command = send_command_to_service(task.service, "escalate", task_id)

        update_state(fn s ->
          tasks = Map.update!(s.unresolved_tasks, task_id, fn t ->
            %{t | status: "expired"}
          end)
          command_queue = [command | s.command_queue]
          %{s | unresolved_tasks: tasks, command_queue: command_queue}
        end)
      end
    end)
  end
end
