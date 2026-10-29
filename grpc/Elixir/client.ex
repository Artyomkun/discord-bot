defmodule ElixirClient.Client do
  @moduledoc """
  Клиент для вызова gRPC сервисов.
  """

  require Logger
  use GRPC.{RPCError, Stub}

  alias Grpc.Proto.Audio.AudioProcessor.Stub, as: AudioStub
  alias Grpc.Proto.Client.ClientService.Stub, as: ClientStub
  alias Grpc.Client.{ServiceDiscovery, RoundRobin, Metrics, ConnectionPool}

  @services %{
    "audio.v1.AudioProcessor" => %{
      port: 50051,
      module: AudioStub,
      method: :process_audio,
      pool_size: 10,
      timeout: 5000
    },
    "client.v1.ClientService" => %{
      port: 50052,
      module: ClientStub,
      method: :handle,
      pool_size: 5,
      timeout: 3000
    }
  }

  @default_timeout 5000
  @max_retries 3
  @pool_cleanup_interval 60_000

  # Геночка
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Клиентский API

  @doc """
  Вызывает gRPC метод по имени сервиса.
  """
  @spec call(String.t(), String.t(), term(), keyword()) ::
    {:ok, term(), map()} | {:error, integer(), String.t()}
  def call(service_name, method_name, request_data, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case Map.get(@services, service_name) do
      nil ->
        {:error, 12, "Unknown service: #{service_name}"}

      config ->
        start_time = System.monotonic_time()

        result = call_with_retry(config, method_name, request_data, timeout, @max_retries)

        duration = System.monotonic_time() - start_time
        Metrics.record_call(service_name, method_name, result, duration)

        result
    end
  end

  @doc """
  Вызывает gRPC метод с явным указанием модуля.
  """
  @spec call(module(), atom(), term(), keyword()) :: {:ok, term()} | {:error, RPCError.t()}
  def call(stub_module, method_name, request, opts \\ []) do
    service_name = get_service_name(stub_module)
    timeout = Keyword.get(opts, :timeout, get_service_timeout(service_name))

    with_channel(service_name, timeout, fn channel ->
      call_stub(stub_module, channel, method_name, request, timeout)
    end)
  end

  @doc """
  Вызывает gRPC метод с балансировкой нагрузки.
  """
  @spec call_balanced(String.t(), String.t(), term(), keyword()) ::
    {:ok, term(), map()} | {:error, integer(), String.t()}
  def call_balanced(service_name, method_name, request_data, opts \\ []) do
    instances = ServiceDiscovery.get_instances(service_name)

    if Enum.empty?(instances) do
      {:error, 14, "No available instances for #{service_name}"}
    else
      instance = RoundRobin.next(service_name, instances)

      opts = Keyword.merge(opts, [
        host: instance.host,
        port: instance.port
      ])

      call(service_name, method_name, request_data, opts)
    end
  end

  @doc """
  Отправляет стрим запросов.
  """
  @spec stream(module(), atom(), Enumerable.t(), keyword()) ::
    {:ok, Enumerable.t()} | {:error, GRPC.RPCError.t()}
  def stream(stub_module, method_name, requests, opts \\ []) do
    service_name = get_service_name(stub_module)
    timeout = Keyword.get(opts, :timeout, get_service_timeout(service_name))

    with_channel(service_name, timeout, fn channel ->
      case apply(stub_module, method_name, [channel, requests, timeout: timeout]) do
        {:ok, stream} -> {:ok, stream}
        {:error, error} -> {:error, error}
      end
    end)
  end

  @doc """
  Проверяет доступность сервиса.
  """
  @spec health_check(String.t()) :: boolean()
  def health_check(service_name) do
    case Map.get(@services, service_name) do
      nil -> false
      config ->
        with_channel(service_name, 2000, fn channel ->
          GRPC.Stub.disconnect(channel)
          true
        end) != {:error, _}
    end
  end

  @doc """
  Проверяет доступность всех сервисов.
  """
  @spec health_check_all() :: %{String.t() => boolean()}
  def health_check_all do
    Map.new(@services, fn {name, _} ->
      {name, health_check(name)}
    end)
  end

  @doc """
  Закрывает все соединения.
  """
  @spec shutdown() :: :ok
  def shutdown do
    Logger.info("Shutting down gRPC client")
    GenServer.stop(__MODULE__)
    :ok
  end

  def init(state) do
    pools = Enum.map(@services, fn {name, config} ->
      {name, ConnectionPool.new(config.pool_size, name, config.port)}
    end) |> Enum.into(%{})

    schedule_cleanup()

    {:ok, %{state | pools: pools}}
  end



  @doc """
  Получает метрики клиента.
  """
  @spec get_metrics() :: map()
  def get_metrics do
    all_metrics = Metrics.get_all()
    pool_metrics = get_pool_metrics()

    # Общая статистика
    total_requests = 0
    successful_requests = 0
    failed_requests = 0
    total_duration = 0

    methods_stats = Enum.reduce(all_metrics, %{}, fn {service, methods}, acc ->
      service_stats = Enum.reduce(methods, %{}, fn {method, stats}, method_acc ->
        total_requests = total_requests + stats.count
        successful_requests = successful_requests + stats.successes
        failed_requests = failed_requests + stats.failures
        total_duration = total_duration + stats.total_duration

        # Получаем гистограмму для метода
        histogram = Metrics.get_histogram(service, method)

        Map.put(method_acc, method, %{
          count: stats.count,
          successes: stats.successes,
          failures: stats.failures,
          success_rate: stats.success_rate,
          avg_duration_ms: stats.avg_duration_us / 1000,
          min_duration_ms: stats.min_duration_us / 1000,
          max_duration_ms: stats.max_duration_us / 1000,
          last_seen: stats.last_seen,
          percentiles: histogram
        })
      end)
      Map.put(acc, service, service_stats)
    end)

    overall = %{
      total_requests: total_requests,
      successful_requests: successful_requests,
      failed_requests: failed_requests,
      success_rate: if total_requests > 0 do
        successful_requests / total_requests * 100
      else
        0.0
      end,
      avg_response_time_ms: if total_requests > 0 do
        (total_duration / total_requests) / 1000
      else
        0.0
      end
    }

    %{
      overall: overall,
      methods: methods_stats,
      pool: pool_metrics
    }
  end

  defp get_pool_metrics do
    pools = Application.get_env(:grpc_client, :pools, [])
    services = get_all_services_from_metrics()
    Enum.reduce(services, %{}, fn service, acc ->
      stats = Grpc.Client.ConnectionPool.get_stats(service)
      Map.put(acc, service, enrich_pool_stats(stats))
    end)
  end

  defp get_all_services_from_metrics do
    :ets.foldl(fn
      {{service, _method}, _}, acc ->
        MapSet.put(acc, service)
      {{:pool, service}, _}, acc ->
        MapSet.put(acc, service)
      _, acc ->
        acc
    end, MapSet.new(), :grpc_client_metrics)
    |> MapSet.to_list()
  end

  defp enrich_pool_stats(nil), do: %{status: :unknown, message: "No connection pool"}

  defp enrich_pool_stats(stats) do
    %{
      total_connections: stats.total_connections || 0,
      active_connections: stats.active_connections || 0,
      idle_connections: stats.idle_connections || 0,
      unhealthy_connections: stats.unhealthy_connections || 0,
      load: calculate_load(stats),
      total_uses: stats.total_uses || 0,
      total_checkouts: stats.checkouts || 0,
      total_checkins: stats.checkins || 0,
      checkout_failures: stats.checkout_failures || 0,
      checkout_success_rate: if (stats.checkouts || 0) > 0 do
        ((stats.checkouts || 0) - (stats.checkout_failures || 0)) / (stats.checkouts || 0) * 100
      else
        100.0
      end,
      created: stats.total_created || 0,
      closed: stats.total_closed || 0,
      errors: stats.total_errors || 0,
      reconnects: stats.total_reconnects || 0,
      avg_age_ms: stats.avg_connection_age || 0,
      addresses: stats.addresses || [],
      status: determine_pool_status(stats),
      last_updated: :os.system_time(:millisecond)
    }
  end

  defp calculate_load(stats) do
    total = stats.total_connections || 0
    active = stats.active_connections || 0
    if total > 0 do
      active / total
    else
      0.0
    end
  end

  defp determine_pool_status(stats) do
    cond do
      stats.total_connections == 0 -> :no_connections
      stats.unhealthy_connections > stats.total_connections / 2 -> :degraded
      stats.checkout_failures > stats.checkouts / 10 -> :overloaded
      true -> :healthy
    end
  end

  def handle_info(:cleanup_pools, state) do
    Enum.each(state.pools, fn {name, pool} ->
      ConnectionPool.cleanup(pool)
    end)

    schedule_cleanup()
    {:noreply, state}
  end

  def terminate(reason, state) do
    Enum.each(state.pools, fn {name, pool} ->
      ConnectionPool.shutdown(pool)
    end)
    :ok
  end

  defp call_with_retry(config, method_name, request_data, timeout, retries_left) do
    service_name = get_service_name(config.module)

    result = with_channel(service_name, timeout, fn channel ->
      call_stub(config.module, channel, method_name, request_data, timeout)
    end)

    case result do
      {:ok, response} ->
        {:ok, response, %{backend: "grpc"}}

      {:error, error} when retries_left > 0 and retryable?(error) ->
        backoff = calculate_backoff(@max_retries - retries_left)
        Logger.warning("gRPC call to #{service_name} failed, retrying in #{backoff}ms (#{retries_left-1} left)")
        :timer.sleep(backoff)
        call_with_retry(config, method_name, request_data, timeout, retries_left - 1)

      {:error, error} ->
        {:error, error.code, error.message}
    end
  end

  defp with_channel(service_name, timeout, fun) do
    case ConnectionPool.checkout(service_name, timeout) do
      {:ok, channel} ->
        try do
          fun.(channel)
        after
          ConnectionPool.checkin(service_name, channel)
        end

      {:error, reason} ->
        Logger.error("Failed to get channel for #{service_name}: #{inspect(reason)}")
        {:error, %RPCError{code: 14, message: "Connection failed"}}
    end
  end

  defp call_stub(stub, channel, method_name, request, timeout) do
    try do
      apply(stub, method_name, [channel, request, timeout: timeout])
    catch
      kind, error ->
        Logger.error("gRPC call to #{inspect(stub)}.#{method_name} failed: #{kind} - #{inspect(error)}")
        {:error, %RPCError{code: 13, message: "Internal error"}}
    end
  end

  defp retryable?(%RPCError{code: code}) when code in [4, 8, 14], do: true
  defp retryable?(_), do: false

  defp calculate_backoff(attempt) do
    base = 100 * (2 ** attempt)
    jitter = :rand.uniform(base)
    base + jitter
  end

  defp get_service_name(AudioStub), do: "audio.v1.AudioProcessor"
  defp get_service_name(ClientStub), do: "client.v1.ClientService"
  defp get_service_name(_), do: "unknown"

  defp get_service_timeout(service_name) do
    case Map.get(@services, service_name) do
      nil -> @default_timeout
      config -> config[:timeout] || @default_timeout
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_pools, @pool_cleanup_interval)
  end
end
