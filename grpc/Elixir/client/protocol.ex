defprotocol ElixirClient.Client.Protocol do
  @moduledoc """
  Протокол для gRPC клиентов с поддержкой пула соединений.

  Позволяет единообразно работать с разными gRPC сервисами.
  """

  @fallback_to_any

  @type request :: term()
  @type response :: {:ok, term()} | {:error, GRPC.RPCError.t()}
  @type stream_response :: {:ok, Enumerable.t()} | {:error, GRPC.RPCError.t()}
  @type metrics :: map()
  @type health_status :: :healthy | :unhealthy | :unknown

  @doc """
  Вызывает gRPC метод.
  """
  @spec call(t(), atom(), request()) :: response()
  def call(client, method, request)

  @doc """
  Вызывает gRPC метод с опциями.
  """
  @spec call(t(), atom(), request(), keyword()) :: response()
  def call(client, method, request, opts)

  @doc """
  Отправляет стрим запросов.
  """
  @spec stream(t(), atom(), Enumerable.t()) :: stream_response()
  def stream(client, method, requests)

  @doc """
  Отправляет стрим запросов с опциями.
  """
  @spec stream(t(), atom(), Enumerable.t(), keyword()) :: stream_response()
  def stream(client, method, requests, opts)

  @doc """
  Получает метрики клиента.
  """
  @spec get_metrics(t()) :: metrics()
  def get_metrics(client)

  @doc """
  Проверяет здоровье клиента.
  """
  @spec health_check(t()) :: health_status()
  def health_check(client)

  @doc """
  Закрывает соединения клиента.
  """
  @spec shutdown(t()) :: :ok
  def shutdown(client)
end
