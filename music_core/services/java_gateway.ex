defmodule MusicCore.Services.JavaGateway do
  @moduledoc """
  Мост к Java Gateway для логирования и аналитики.
  """

  require Logger

  alias MusicCore.JavaGateway.Client

  # Порты сервисов (согласованные с Java кодом)
  @java_gateway_port 8081      # Java Gateway (сервер)
  @go_processor_port 8082      # Go сервис (обработка аудио)
  @elixir_grpc_port 4000       # Elixir gRPC сервер
  @python_bot_port 50052       # Python бот

  @default_timeout 8000
  @default_host "localhost"

  @doc """
  Отправляет аудио данные на обработку в Java Gateway.
  """
  def process_audio(stream_id, audio_data, effects, options \\ []) do
    port = Keyword.get(options, :port, @java_gateway_port)
    host = Keyword.get(options, :host, @default_host)

    Logger.debug("[JavaGateway] Processing audio: stream_id=#{stream_id}, host=#{host}:#{port}")

    case Client.process_audio(stream_id, audio_data, effects, options) do
      {:ok, result} ->
        Logger.debug("[JavaGateway] Successfully processed stream #{stream_id}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("[JavaGateway] Failed to process stream #{stream_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Проверяет доступность Java Gateway.
  """
  def health_check do
    case Client.health_check() do
      :ok ->
        Logger.debug("[JavaGateway] Health check passed")
        :ok

      {:error, reason} ->
        Logger.warning("[JavaGateway] Health check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Проверяет доступность Go сервиса.
  """
  def go_health_check do
    port = Application.get_env(:music_core, :go_service, %{})[:port] || @go_processor_port
    case Client.health_check(port: port) do
      :ok ->
        Logger.debug("[JavaGateway] Go service health check passed")
        :ok
      {:error, reason} ->
        Logger.warning("[JavaGateway] Go service health check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Проверяет доступность Python бота.
  """
  def python_health_check do
    port = Application.get_env(:music_core, :python_bot, %{})[:port] || @python_bot_port
    case Client.health_check(port: port) do
      :ok ->
        Logger.debug("[JavaGateway] Python bot health check passed")
        :ok
      {:error, reason} ->
        Logger.warning("[JavaGateway] Python bot health check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Проверяет доступность Elixir gRPC сервера.
  """
  def elixir_health_check do
    port = Application.get_env(:music_core, :elixir_grpc, %{})[:port] || @elixir_grpc_port
    case Client.health_check(port: port, path: "/health") do
      :ok ->
        Logger.debug("[JavaGateway] Elixir gRPC health check passed")
        :ok
      {:error, reason} ->
        Logger.warning("[JavaGateway] Elixir gRPC health check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Отправляет аудио на обработку с таймаутом и fallback.
  """
  def process_audio_with_timeout(stream_id, audio_data, effects, timeout \\ @default_timeout, fallback \\ nil) do
    task = Task.async(fn ->
      process_audio(stream_id, audio_data, effects)
    end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result
      nil ->
        Logger.error("[JavaGateway] Timeout processing stream #{stream_id} after #{timeout}ms")
        fallback
    end
  end

  @doc """
  Отправляет команду в Go сервис через Java Gateway.
  """
  def send_to_go(command, params, options \\ []) do
    port = Keyword.get(options, :port, @go_processor_port)
    Logger.debug("[JavaGateway] Sending command '#{command}' to Go service (port #{port})")

    case Client.send_go_command(command, params, options) do
      {:ok, response} ->
        Logger.debug("[JavaGateway] Go service responded successfully")
        {:ok, response}
      {:error, reason} ->
        Logger.error("[JavaGateway] Go service command failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Отправляет команду в Python бота через Java Gateway.
  """
  def send_to_python(command, params, options \\ []) do
    port = Keyword.get(options, :port, @python_bot_port)
    Logger.debug("[JavaGateway] Sending command '#{command}' to Python bot (port #{port})")

    case Client.send_python_command(command, params, options) do
      {:ok, response} ->
        Logger.debug("[JavaGateway] Python bot responded successfully")
        {:ok, response}
      {:error, reason} ->
        Logger.error("[JavaGateway] Python bot command failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Получает статус всех сервисов.
  """
  def services_status do
    %{
      java_gateway: health_check(),
      go_service: go_health_check(),
      python_bot: python_health_check(),
      elixir_grpc: elixir_health_check(),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Очистка старых данных в Java Gateway.
  """
  def cleanup(older_than_days \\ 30) do
    Logger.info("[JavaGateway] Cleaning up data older than #{older_than_days} days")

    case Client.cleanup_database(%{older_than_days: older_than_days}) do
      {:ok, result} ->
        Logger.info("[JavaGateway] Cleanup completed: #{inspect(result)}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("[JavaGateway] Cleanup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
