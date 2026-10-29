defmodule ElixirClient.Client.Service do
  @moduledoc """
  gRPC клиент для ClientService.

  Обрабатывает:
  - Аутентификацию
  - Подписки на события
  - Управление сессиями
  - Пул соединений
  - Таймауты и ретраи
  - Метрики и мониторинг
  """

  use GRPC.{RPCError, Stub, Client}, service: Grpc.Proto.Client.ClientService.Service

  alias Grpc.Proto.Client.{
    ClientRequest,
    ClientResponse,
    AuthRequest,
    SubscribeRequest,
    UnsubscribeRequest,
    HeartbeatRequest,
    SessionInfoRequest
  }
  alias Grpc.Proto.Client.ClientService.Stub, as: ClientStub

  require Logger

  @default_timeout 5000
  @max_retries 3
  @pool_size 10

  # Клиентский API

  @doc """
  Обрабатывает клиентский запрос с поддержкой пула и таймаутов.
  """
  @spec handle(ClientRequest.t(), keyword()) ::
    {:ok, ClientResponse.t()} | {:error, RPCError.t()}
  def handle(request, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    with_channel(fn channel ->
      ClientStub.handle(channel, request, timeout: timeout)
    end)
  end

  @doc """
  Аутентифицирует клиента с кэшированием результата.
  """
  @spec authenticate(String.t(), atom(), keyword()) ::
    {:ok, map()} | {:error, RPCError.t()}
  def authenticate(token, client_type, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Проверяем кэш
    case Cache.get("auth:#{token}") do
      {:ok, cached} ->
        Metrics.cache_hit(:auth)
        {:ok, cached}

      {:error, :not_found} ->
        do_authenticate(token, client_type, timeout)
    end
  end

  @doc """
  Подписывает клиента на события.
  """
  @spec subscribe(String.t(), list(String.t()), keyword()) :: :ok | {:error, RPCError.t()}
  def subscribe(client_id, events, opts \\ []) do
    request = SubscribeRequest.new(
      client_id: client_id,
      events: events,
      timestamp: DateTime.utc_now() |> DateTime.to_unix()
    )

    with_retry(fn -> handle_subscribe(request, opts) end, opts)
  end

  @doc """
  Отписывает клиента от событий.
  """
  @spec unsubscribe(String.t(), list(String.t())) ::
    :ok | {:error, RPCError.t()}
  def unsubscribe(client_id, events) do
    request = UnsubscribeRequest.new(
      client_id: client_id,
      events: events
    )

    case handle_subscribe(request, []) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Отправляет heartbeat для поддержания сессии.
  """
  @spec heartbeat(String.t()) :: :ok | {:error, RPCError.t()}
  def heartbeat(client_id) do
    request = HeartbeatRequest.new(
      client_id: client_id,
      timestamp: System.system_time(:millisecond)
    )

    case handle_heartbeat(request) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Получает информацию о сессии.
  """
  @spec get_session_info(String.t()) :: {:ok, map()} | {:error, GRPC.RPCError.t()}
  def get_session_info(client_id) do
    request = SessionInfoRequest.new(client_id: client_id)

    case handle_session_info(request) do
      {:ok, response} ->
        {:ok, %{
          created_at: response.created_at,
          last_heartbeat: response.last_heartbeat,
          events_count: response.events_count,
          active_subscriptions: response.active_subscriptions
        }}
      {:error, error} ->
        {:error, error}
    end
  end

  # Приватные функции для обработки

  defp do_authenticate(token, client_type, timeout) do
    request = AuthRequest.new(
      token: token,
      client_type: client_type,
      timestamp: System.system_time(:millisecond)
    )

    result = with_retry(fn -> handle_auth(request, timeout) end, timeout: timeout)

    # Кэшируем успешный результат
    case result do
      {:ok, response} ->
        Cache.put("auth:#{token}", response, ttl: 3600)
        Metrics.cache_miss(:auth)
      _ -> :ok
    end

    result
  end

  defp handle_auth(request, timeout) do
    with_channel(fn channel ->
      case ClientStub.authenticate(channel, request, timeout: timeout) do
        {:ok, response} ->
          {:ok, %{
            client_id: response.client_id,
            name: response.name,
            expires_at: response.expires_at,
            permissions: response.permissions
          }}
        {:error, error} ->
          {:error, error}
      end
    end)
  end

  defp handle_subscribe(request, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    with_channel(fn channel ->
      ClientStub.subscribe(channel, request, timeout: timeout)
    end)
  end

  defp handle_heartbeat(request) do
    with_channel(fn channel ->
      ClientStub.heartbeat(channel, request, timeout: @default_timeout)
    end)
  end

  defp handle_session_info(request) do
    with_channel(fn channel ->
      ClientStub.get_session_info(channel, request, timeout: @default_timeout)
    end)
  end

  # Управление соединениями

  defp with_channel(fun) do
    case ConnectionPool.checkout(:client_service) do
      {:ok, channel} ->
        try do
          fun.(channel)
        after
          ConnectionPool.checkin(:client_service, channel)
        end
      {:error, reason} ->
        Logger.error("Failed to get channel: #{inspect(reason)}")
        {:error, %GRPC.RPCError{code: 14, message: "Connection failed"}}
    end
  end

  defp with_retry(fun, opts) do
    retries = Keyword.get(opts, :retries, @max_retries)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    do_with_retry(fun, retries, timeout)
  end

  defp do_with_retry(fun, 0, _timeout) do
    fun.()
  end

  defp do_with_retry(fun, n, timeout) do
    case fun.() do
      {:error, %RPCError{code: code}} = error when code in [4, 8, 14] ->
        # Deadline, ResourceExhausted, Unavailable
        Logger.warning("Retryable error (#{code}), #{n-1} retries left")
        :timer.sleep(100 * (4 - n))
        do_with_retry(fun, n-1, timeout)

      result ->
        result
    end
  end
end
