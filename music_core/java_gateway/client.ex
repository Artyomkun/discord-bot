defmodule MusicCore.JavaGateway.Client do
  @moduledoc """
  Клиент для взаимодействия с Java Gateway.

  Координирует работу между Elixir, Go и Python сервисами.
  """

  require Logger

  alias MusicCore.{Metrics, Cache, Config}

  @java_gateway_url "http://localhost:8081"

  @doc """
  Отправляет запрос на обработку аудио через Java Gateway.
  """
  @spec process_audio(String.t(), binary(), list(), map()) :: {:ok, map()} | {:error, term()}
  def process_audio(stream_id, audio_data, effects, options \\ %{}) do
    Metrics.record(:audio_processing_start, 1, %{stream_id: stream_id, gateway: :java})

    request_body = %{
      stream_id: stream_id,
      audio_data: Base.encode64(audio_data),
      effects: effects,
      options: options,
      timestamp: System.system_time(:millisecond)
    }

    case make_request("/api/audio/process", request_body) do
      {:ok, response} ->
        Metrics.record(:audio_processing_stop, 1, %{stream_id: stream_id, status: :success, gateway: :java})
        {:ok, response}

      {:error, reason} ->
        Metrics.record(:audio_processing_error, 1, %{stream_id: stream_id, error: reason, gateway: :java})
        {:error, reason}
    end
  end

  @doc """
  Регистрирует Python клиента в gateway.
  """
  @spec register_python_client(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def register_python_client(client_id, capabilities) do
    request_body = %{
      client_id: client_id,
      type: "python",
      capabilities: capabilities,
      registered_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    make_request("/api/clients/register", request_body)
  end

  @doc """
  Отправляет команду Discord боту через Python клиента.
  """
  @spec send_discord_command(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def send_discord_command(client_id, command, params) do
    request_body = %{
      client_id: client_id,
      command: command,
      params: params,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case make_request("/api/discord/command", request_body) do
      {:ok, response} ->
        Metrics.record(:discord_command_sent, 1, %{command: command, client_id: client_id})
        {:ok, response}

      {:error, reason} ->
        Metrics.record(:discord_command_failed, 1, %{command: command, client_id: client_id, error: reason})
        {:error, reason}
    end
  end

  @doc """
  Получает статус всех подключенных клиентов.
  """
  @spec get_clients_status() :: {:ok, map()} | {:error, term()}
  def get_clients_status do
    make_request("/api/clients/status", %{}, :get)
  end

  @doc """
  Синхронизирует состояние между сервисами.
  """
  @spec sync_state(atom(), map()) :: {:ok, map()} | {:error, term()}
  def sync_state(service, state) do
    request_body = %{
      service: Atom.to_string(service),
      state: state,
      sync_timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    make_request("/api/sync/state", request_body)
  end

  @doc """
  Проверяет здоровье Java Gateway.
  """
  @spec health_check() :: boolean()
  def health_check do
    case make_request("/health", %{}, :get) do
      {:ok, %{"status" => "healthy"}} -> true
      _ -> false
    end
  end

  @doc """
  Проверяет здоровье Go сервиса.
  """
  @spec go_health_check() :: boolean()
  def go_health_check do
    case make_request("/api/go/health", %{}, :get) do
      {:ok, %{"status" => "healthy"}} -> true
      _ -> false
    end
  end

  @doc """
  Проверяет здоровье Python бота.
  """
  @spec python_health_check() :: boolean()
  def python_health_check do
    case make_request("/api/python/health", %{}, :get) do
      {:ok, %{"status" => "healthy"}} -> true
      _ -> false
    end
  end

  @doc """
  Получает метрики Java Gateway.
  """
  @spec get_metrics() :: {:ok, map()} | {:error, term()}
  def get_metrics do
    make_request("/metrics", %{}, :get)
  end

  @doc """
  Создает задачу для фоновой обработки.
  """
  @spec create_background_task(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def create_background_task(task_type, payload) do
    request_body = %{
      task_type: task_type,
      payload: payload,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    case make_request("/api/tasks/create", request_body) do
      {:ok, %{"task_id" => task_id}} ->
        Metrics.record(:background_task_created, 1, %{task_type: task_type})
        {:ok, task_id}

      {:ok, response} ->
        {:error, {:unexpected_response, response}}

      {:error, reason} ->
        Metrics.record(:background_task_creation_failed, 1, %{task_type: task_type, error: reason})
        {:error, reason}
    end
  end

  @doc """
  Получает статус фоновой задачи.
  """
  @spec get_task_status(String.t()) :: {:ok, map()} | {:error, term()}
  def get_task_status(task_id) do
    make_request("/api/tasks/#{task_id}/status", %{}, :get)
  end

  @doc """
  Очищает старые записи из базы данных.
  """
  @spec cleanup_database(keyword()) :: {:ok, map()} | {:error, term()}
  def cleanup_database(opts \\ []) do
    older_than_days = Keyword.get(opts, :older_than_days, 30)
    tables = Keyword.get(opts, :tables, ["audit_logs", "sessions", "temp_data"])
    dry_run = Keyword.get(opts, :dry_run, false)

    request_body = %{
      action: "cleanup",
      older_than_days: older_than_days,
      tables: tables,
      dry_run: dry_run
    }

    case make_request("/api/database/cleanup", request_body) do
      {:ok, response} ->
        Logger.info("Database cleanup completed: #{inspect(response)}")
        {:ok, response}

      {:error, reason} ->
        Logger.error("Database cleanup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ========== PRIVATE ==========

  defp make_request(path, body \\ %{}, method \\ :post) do
    url = @java_gateway_url <> path
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"X-Service", "elixir"}
    ]

    request_body = Jason.encode!(body)

    http_opts = [
      connect_timeout: 5000,
      timeout: 10000,
      max_redirects: 3
    ]

    case :httpc.request(method, {url, headers, 'application/json', request_body}, http_opts, []) do
      {:ok, {{_version, 200, _reason}, _headers, response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:ok, {{_version, status_code, reason}, _headers, response_body}} ->
        Logger.warning("Java Gateway request failed: #{status_code} #{reason}")
        Logger.debug("Response body: #{response_body}")
        {:error, {:http_error, status_code, reason}}

      {:error, reason} ->
        Logger.error("Failed to connect to Java Gateway: #{inspect(reason)}")
        {:error, {:connection_error, reason}}
    end
  rescue
    error ->
      Logger.error("Exception in Java Gateway request: #{inspect(error)}")
      {:error, {:exception, error}}
  end
end
