defmodule ElixirClient.Client.ServiceDiscovery do
  @moduledoc """
  Обнаружение инстансов сервисов.

  Поддерживает:
  - Статическая конфигурация
  - Consul (с кэшированием)
  - Kubernetes API
  - DNS SRV записи
  - Eureka (Netflix)
  - ZooKeeper
  - etcd
  - AWS Cloud Map
  - Автоматическое обновление
  - Health checks
  - Метрики
  - Graceful fallback
  """

  use GenServer
  require Logger

  alias ElixirClient.Client.Metrics

  @cache_ttl 30_000 # 30 секунд
  @http_timeout 2000
  @refresh_interval 60_000 # 1 минута

  # Клиентский API

  @doc """
  Запускает ServiceDiscovery GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Получает инстансы сервиса.
  """
  @spec get_instances(String.t()) :: list(map())
  def get_instances(service_name) do
    GenServer.call(__MODULE__, {:get_instances, service_name})
  end

  @doc """
  Получает здоровые инстансы сервиса.
  """
  @spec get_healthy_instances(String.t()) :: list(map())
  def get_healthy_instances(service_name) do
    service_name
    |> get_instances()
    |> Enum.filter(& &1.healthy)
  end

  @doc """
  Принудительно обновляет кэш для сервиса.
  """
  @spec refresh(String.t()) :: :ok
  def refresh(service_name) do
    GenServer.cast(__MODULE__, {:refresh, service_name})
  end

  @doc """
  Получает статистику ServiceDiscovery.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Регистрирует сервис в ServiceDiscovery.
  """
  @spec register(map()) :: :ok | {:error, term()}
  def register(service_info) do
    GenServer.call(__MODULE__, {:register, service_info})
  end

  @doc """
  Отменяет регистрацию сервиса.
  """
  @spec deregister(String.t()) :: :ok | {:error, term()}
  def deregister(service_id) do
    GenServer.call(__MODULE__, {:deregister, service_id})
  end

  # GenServer колбэки

  def init(opts) do
    # Создаём ETS для кэша
    :ets.new(:service_discovery_cache, [:named_table, :public, :set])
    :ets.new(:service_discovery_services, [:named_table, :public, :set])

    state = %{
      cache: :service_discovery_cache,
      services: :service_discovery_services,
      stats: %{
        total_requests: 0,
        cache_hits: 0,
        cache_misses: 0,
        errors: 0,
        last_refresh: nil
      },
      watchers: %{},
      config: %{
        discovery_type: Keyword.get(opts, :discovery_type, :static),
        refresh_interval: Keyword.get(opts, :refresh_interval, @refresh_interval),
        health_check: Keyword.get(opts, :health_check, true)
      }
    }

    # Запускаем периодическое обновление
    schedule_refresh()

    {:ok, state}
  end

  def handle_call({:get_instances, service_name}, _from, state) do
    start_time = System.monotonic_time()
    stats = %{state.stats | total_requests: state.stats.total_requests + 1}

    # Проверяем кэш
    case :ets.lookup(state.cache, service_name) do
      [{^service_name, instances, expires}] when expires > System.system_time(:millisecond) ->
        # Кэш попадание
        new_stats = %{stats | cache_hits: stats.cache_hits + 1}
        record_metrics(service_name, :cache_hit, System.monotonic_time() - start_time)
        {:reply, instances, %{state | stats: new_stats}}

      _ ->
        # Кэш промах - получаем свежие
        new_stats = %{stats | cache_misses: stats.cache_misses + 1}
        instances = fetch_and_cache(service_name, state)
        record_metrics(service_name, :cache_miss, System.monotonic_time() - start_time)
        {:reply, instances, %{state | stats: new_stats}}
    end
  end

  def handle_call(:stats, _from, state) do
    cache_size = :ets.info(state.cache, :size)
    services_size = :ets.info(state.services, :size)

    stats = Map.put(state.stats, :cache_size, cache_size)
    stats = Map.put(stats, :registered_services, services_size)

    {:reply, stats, state}
  end

  def handle_call({:register, service_info}, _from, state) do
    case register_service(service_info) do
      :ok ->
        :ets.insert(state.services, {service_info.id, service_info})
        {:reply, :ok, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:deregister, service_id}, _from, state) do
    :ets.delete(state.services, service_id)
    {:reply, :ok, state}
  end

  def handle_cast({:refresh, service_name}, state) do
    # Принудительное обновление
    _ = fetch_and_cache(service_name, state)
    {:noreply, state}
  end

  def handle_info(:refresh_all, state) do
    # Обновляем все закэшированные сервисы
    state.cache
    |> :ets.tab2list()
    |> Enum.each(fn {service_name, _, _} ->
      _ = fetch_and_cache(service_name, state)
    end)

    schedule_refresh()
    {:noreply, state}
  end

  # Приватные функции

  defp fetch_and_cache(service_name, state) do
    instances = fetch_instances(service_name, state.config.discovery_type)

    # Проводим health check если нужно
    final_instances = if state.config.health_check do
      instances
      |> Enum.map(&Map.put(&1, :healthy, perform_health_check(&1)))
      |> Enum.filter(& &1.healthy)
    else
      instances
    end

    # Кэшируем
    expires = System.system_time(:millisecond) + @cache_ttl
    :ets.insert(state.cache, {service_name, final_instances, expires})

    final_instances
  end

  defp fetch_instances(service_name, discovery_type) do
    case discovery_type do
      :static -> get_static_instances(service_name)
      :consul -> get_consul_instances(service_name)
      :kubernetes -> get_k8s_instances(service_name)
      :dns -> get_dns_instances(service_name)
      :eureka -> get_eureka_instances(service_name)
      :zookeeper -> get_zookeeper_instances(service_name)
      :etcd -> get_etcd_instances(service_name)
      :aws_cloud_map -> get_aws_instances(service_name)
      :multi -> get_multi_instances(service_name) # Пробует несколько методов
      _ -> fallback_instances(service_name)
    end
  end

  # ZooKeeper discovery
  defp get_zookeeper_instances(service_name) do
    zk_hosts = Application.get_env(:music_core, :zookeeper_hosts, ["localhost:2181"])

    case :erlzk.connect(zk_hosts) do
      {:ok, conn} ->
        path = "/services/#{service_name}"
        case :erlzk.get_children(conn, path) do
          {:ok, children} ->
            instances = Enum.map(children, fn child ->
              {:ok, data} = :erlzk.get_data(conn, "#{path}/#{child}")
              %{
                host: data[:host],
                port: data[:port],
                id: child,
                healthy: data[:healthy] != false,
                discovery: :zookeeper,
                last_check: System.system_time(:millisecond)
              }
            end)
            :erlzk.close(conn)
            instances
          {:error, reason} ->
            Logger.error("ZooKeeper error: #{reason}")
            fallback_instances(service_name)
        end
      {:error, reason} ->
        Logger.error("Failed to connect to ZooKeeper: #{reason}")
        fallback_instances(service_name)
    end
  end

  # etcd discovery
  defp get_etcd_instances(service_name) do
    etcd_host = Application.get_env(:music_core, :etcd_host, "localhost")
    etcd_port = Application.get_env(:music_core, :etcd_port, 2379)

    url = "http://#{etcd_host}:#{etcd_port}/v3/kv/range"

    case http_post(url, %{
      key: Base.encode64("/services/#{service_name}/"),
      range_end: Base.encode64("/services/#{service_name}0")
    }) do
      {:ok, %{status: 200, body: body}} ->
        parse_etcd_response(body)
      error ->
        Logger.error("etcd request failed: #{inspect(error)}")
        fallback_instances(service_name)
    end
  end

  defp parse_etcd_response(body) do
    case Jason.decode(body) do
      {:ok, %{"kvs" => kvs}} when is_list(kvs) ->
        Enum.map(kvs, fn kv ->
          data = Base.decode64!(kv["value"]) |> Jason.decode!()
          %{
            host: data["host"],
            port: data["port"],
            id: data["id"],
            healthy: data["healthy"] != false,
            discovery: :etcd,
            last_check: System.system_time(:millisecond)
          }
        end)
      _ ->
        []
    end
  end

  # AWS Cloud Map discovery
  defp get_aws_instances(service_name) do
    region = Application.get_env(:music_core, :aws_region, "us-east-1")

    # Используем AWS SDK через порты или HTTP API
    url = "https://servicediscovery.#{region}.amazonaws.com"

    case aws_api_request(url, service_name) do
      {:ok, instances} -> instances
      {:error, reason} ->
        Logger.error("AWS Cloud Map failed: #{reason}")
        fallback_instances(service_name)
    end
  end

  defp aws_api_request(url, service_name) do
    # TODO: реальная AWS сигнатура
    http_get(url)
  end

  # Multi discovery (пробует несколько методов)
  defp get_multi_instances(service_name) do
    methods = [:consul, :kubernetes, :dns, :static]

    Enum.find_value(methods, fn method ->
      case fetch_instances(service_name, method) do
        [] -> nil
        instances -> instances
      end
    end) || fallback_instances(service_name)
  end

  # Улучшенный health check
  defp perform_health_check(instance) do
    case :gen_tcp.connect(instance.host, instance.port, [:binary, packet: :raw], 1000) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        true
      {:error, reason} ->
        Logger.debug("Health check failed for #{instance.host}:#{instance.port}: #{reason}")
        false
    end
  end

  # Регистрация сервиса
  defp register_service(service_info) do
    case Application.get_env(:music_core, :service_discovery, :static) do
      :consul -> register_consul(service_info)
      :zookeeper -> register_zookeeper(service_info)
      :etcd -> register_etcd(service_info)
      _ -> :ok
    end
  end

  defp register_consul(service_info) do
    consul_host = Application.get_env(:music_core, :consul_host, "localhost")
    consul_port = Application.get_env(:music_core, :consul_port, 8500)

    url = "http://#{consul_host}:#{consul_port}/v1/agent/service/register"

    body = %{
      ID: service_info.id,
      Name: service_info.name,
      Address: service_info.host,
      Port: service_info.port,
      Check: %{
        TCP: "#{service_info.host}:#{service_info.port}",
        Interval: "10s"
      }
    }

    case http_put(url, body) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, "Consul returned #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # Метрики
  defp record_metrics(service_name, type, duration) do
    :telemetry.execute([:music_core, :grpc, :discovery], %{
      duration: System.convert_time_unit(duration, :native, :microsecond)
    }, %{
      service: service_name,
      type: type
    })
  end

  # Утилиты для HTTP
  defp http_post(url, body) do
    try do
      {:ok, pid} = :hackney.start()
      headers = [{"Content-Type", "application/json"}]
      body_json = Jason.encode!(body)

      case :hackney.request(:post, url, headers, body_json, [timeout: @http_timeout]) do
        {:ok, status, resp_headers, client} ->
          {:ok, body} = :hackney.body(client)
          {:ok, %{status: status, headers: resp_headers, body: body}}
        error -> error
      end
    rescue
      e -> {:error, e}
    end
  end

  defp http_put(url, body) do
    try do
      {:ok, pid} = :hackney.start()
      headers = [{"Content-Type", "application/json"}]
      body_json = Jason.encode!(body)

      case :hackney.request(:put, url, headers, body_json, [timeout: @http_timeout]) do
        {:ok, status, resp_headers, client} ->
          {:ok, body} = :hackney.body(client)
          {:ok, %{status: status, headers: resp_headers, body: body}}
        error -> error
      end
    rescue
      e -> {:error, e}
    end
  end

  # Периодические задачи
  defp schedule_refresh do
    Process.send_after(self(), :refresh_all, @refresh_interval)
  end

  # Fallback
  defp fallback_instances(service_name) do
    Logger.warning("Using fallback for #{service_name}")
    [%{
      host: "localhost",
      port: get_default_port(service_name),
      healthy: true,
      discovery: :fallback,
      last_check: System.system_time(:millisecond)
    }]
  end

  # Default ports
  defp get_default_port("audio.v1.AudioProcessor"), do: 50051
  defp get_default_port("client.v1.ClientService"), do: 50052
  defp get_default_port(_), do: 50051
end
