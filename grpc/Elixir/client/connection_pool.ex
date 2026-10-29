defmodule ElixirClient.Client.ConnectionPool do
  @moduledoc """
  Пул gRPC соединений с автоматическим управлением.

  Поддерживает:
  - Динамическое масштабирование
  - Health checks
  - Метрики
  - Graceful shutdown
  - Автоочистку
  - Мониторинг соединений
  - Кэширование каналов
  - Автоматическое переподключение
  - Логирование состояния
  - Детальную статистику
  """

  use GenServer
  require Logger

  alias ElixirClient.Client.Metrics

  # Типажи
  @type pool_config :: %{
    name: atom(),
    size: pos_integer(),
    max_overflow: pos_integer(),
    strategy: :fifo | :lifo,
    host: String.t(),
    port: :inet.port_number(),
    service: String.t(),
    timeout: pos_integer(),
    reconnect_delay: pos_integer(),
    max_reconnects: pos_integer()
  }

  @type pool_state :: %{
    pool: pid(),
    service: String.t(),
    size: pos_integer(),
    host: String.t(),
    port: :inet.port_number(),
    stats: %{
      created: non_neg_integer(),
      checked_out: non_neg_integer(),
      checked_in: non_neg_integer(),
      failures: non_neg_integer(),
      reconnects: non_neg_integer(),
      last_health_check: integer() | nil,
      last_cleanup: integer() | nil,
      last_reconnect: integer() | nil
    },
    monitors: %{reference() => pid()},
    cache: :ets.tid(),
    config: pool_config(),
    reconnect_attempts: %{pid() => non_neg_integer()},
    backoff: %{pid() => non_neg_integer()}
  }

  # Клиентский API

  @doc """
  Создаёт новый пул соединений.
  """
  @spec new(integer(), String.t(), integer(), keyword()) :: pid()
  def new(size, service_name, port, opts \\ []) do
    name = Keyword.get(opts, :name, pool_name(service_name))

    {:ok, pool} = :poolboy.start_link(
      pool_config(size, service_name, opts),
      [host: Keyword.get(opts, :host, "localhost"), port: port, service: service_name]
    )
    pool
  end

  @doc """
  Получает соединение из пула.
  """
  @spec checkout(String.t(), timeout()) :: {:ok, pid()} | {:error, atom()}
  def checkout(service_name, timeout \\ 5000) do
    pool = pool_name(service_name)

    case :poolboy.checkout(pool, true, timeout) do
      worker when is_pid(worker) ->
        Metrics.record_checkout(service_name)
        {:ok, worker}

      :full ->
        Metrics.record_checkout_failure(service_name, :full)
        {:error, :no_available_channels}

      other ->
        Metrics.record_checkout_failure(service_name, other)
        {:error, other}
    end
  end

  @doc """
  Возвращает соединение в пул.
  """
  @spec checkin(String.t(), pid()) :: :ok
  def checkin(service_name, worker) do
    pool = pool_name(service_name)
    :poolboy.checkin(pool, worker)
    Metrics.record_checkin(service_name)
    :ok
  end

  @doc """
  Транзакция с соединением.
  """
  @spec transaction(String.t(), (pid() -> any()), keyword()) :: any()
  def transaction(service_name, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    retries = Keyword.get(opts, :retries, 1)

    do_transaction(service_name, fun, timeout, retries)
  end

  @doc """
  Получает кэшированное соединение.
  """
  @spec get_cached(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_cached(service_name) do
    case :ets.lookup(:grpc_channel_cache, service_name) do
      [{^service_name, channel, expires}] when expires > System.system_time(:millisecond) ->
        {:ok, channel}
      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Кэширует соединение.
  """
  @spec cache(String.t(), pid(), integer()) :: :ok
  def cache(service_name, channel, ttl \\ 60_000) do
    expires = System.system_time(:millisecond) + ttl
    :ets.insert(:grpc_channel_cache, {service_name, channel, expires})
    :ok
  end

  @doc """
  Очищает пул (удаляет неиспользуемые соединения).
  """
  @spec cleanup(pid()) :: :ok
  def cleanup(pool) do
    GenServer.cast(pool, :cleanup)
  end

  @doc """
  Останавливает пул.
  """
  @spec shutdown(pid()) :: :ok
  def shutdown(pool) do
    GenServer.stop(pool)
  end

  @doc """
  Получает статус пула.
  """
  @spec status(String.t()) :: {:ok, map()} | {:error, atom()}
  def status(service_name) do
    pool = pool_name(service_name)

    case :poolboy.status(pool) do
      {available, overflow, workers} ->
        {:ok, %{
          available: available,
          overflow: overflow,
          workers: workers,
          total: available + overflow + workers
        }}
      other ->
        {:error, other}
    end
  end

  @doc """
  Получает детальную статистику пула.
  """
  @spec stats(pid()) :: map()
  def stats(pool) do
    GenServer.call(pool, :get_stats)
  end

  @doc """
  Принудительно переподключает все соединения.
  """
  @spec reconnect_all(pid()) :: :ok
  def reconnect_all(pool) do
    GenServer.cast(pool, :reconnect_all)
  end

  # GenServer колбэки

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  def init(opts) do
    Process.flag(:trap_exit, true)

    size = Keyword.get(opts, :size, 10)
    max_overflow = Keyword.get(opts, :max_overflow, 2)
    strategy = Keyword.get(opts, :strategy, :fifo)
    service = Keyword.get(opts, :service, "unknown")
    port = Keyword.get(opts, :port, 50051)
    host = Keyword.get(opts, :host, "localhost")
    timeout = Keyword.get(opts, :timeout, 5000)
    reconnect_delay = Keyword.get(opts, :reconnect_delay, 1000)
    max_reconnects = Keyword.get(opts, :max_reconnects, 5)

    # Создаём ETS для кэша
    :ets.new(:grpc_channel_cache, [:named_table, :public, :set])

    # Запускаем пул через poolboy
    pool_config = [
      {:name, {:local, pool_name(service)}},
      {:worker_module, GRPC.Stub},
      {:size, size},
      {:max_overflow, max_overflow},
      {:strategy, strategy},
      {:auto_ack, false}
    ]

    worker_args = [host: host, port: port, service: service]

    case :poolboy.start_link(pool_config, worker_args) do
      {:ok, pool} ->
        state = %{
          pool: pool,
          service: service,
          size: size,
          host: host,
          port: port,
          stats: %{
            created: 0,
            checked_out: 0,
            checked_in: 0,
            failures: 0,
            reconnects: 0,
            last_health_check: nil,
            last_cleanup: nil,
            last_reconnect: nil
          },
          monitors: %{},
          cache: :grpc_channel_cache,
          config: %{
            name: pool_name(service),
            size: size,
            max_overflow: max_overflow,
            strategy: strategy,
            host: host,
            port: port,
            service: service,
            timeout: timeout,
            reconnect_delay: reconnect_delay,
            max_reconnects: max_reconnects
          },
          reconnect_attempts: %{},
          backoff: %{}
        }

        # Запускаем периодические задачи
        schedule_health_check()
        schedule_metrics()
        schedule_cleanup()

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_call(:get_stats, _from, state) do
    case :poolboy.status(state.pool) do
      {available, overflow, workers} ->
        pool_status = %{
          available: available,
          overflow: overflow,
          workers: workers,
          total: available + overflow + workers,
          utilization: if(state.size > 0, do: (workers + overflow) / state.size, else: 0)
        }

        # Получаем статус каждого воркера
        worker_status = Enum.map(state.monitors, fn {ref, pid} ->
          {inspect(pid), %{
            attempts: Map.get(state.reconnect_attempts, pid, 0),
            backoff: Map.get(state.backoff, pid, 0)
          }}
        end) |> Enum.into(%{})

        stats = state.stats
        |> Map.put(:pool_status, pool_status)
        |> Map.put(:worker_status, worker_status)

        {:reply, stats, state}

      other ->
        {:reply, {:error, other}, state}
    end
  end

  def handle_cast(:cleanup, state) do
    # Очищаем неиспользуемые соединения
    :poolboy.child_spec(state.pool, [])

    # Очищаем просроченный кэш
    now = System.system_time(:millisecond)
    :ets.foldl(fn
      {service, _channel, expires} = key, _ when expires < now ->
        :ets.delete_object(:grpc_channel_cache, key)
      _, _ -> :ok
    end, :ok, :grpc_channel_cache)

    stats = %{state.stats | last_cleanup: now}
    {:noreply, %{state | stats: stats}}
  end

  def handle_cast(:reconnect_all, state) do
    # Переподключаем все соединения
    Enum.each(state.monitors, fn {_ref, pid} ->
      reconnect_worker(pid, state)
    end)

    stats = %{state.stats | last_reconnect: System.system_time(:millisecond)}
    {:noreply, %{state | stats: stats}}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning("Worker #{inspect(pid)} exited: #{inspect(reason)}")

    # Пытаемся переподключить
    attempts = Map.get(state.reconnect_attempts, pid, 0)

    if attempts < state.config.max_reconnects do
      backoff = state.config.reconnect_delay * (2 ** attempts)
      Logger.info("Reconnecting worker #{inspect(pid)} in #{backoff}ms (attempt #{attempts + 1})")

      # Запускаем переподключение
      Process.send_after(self(), {:reconnect, pid}, backoff)

      new_attempts = Map.put(state.reconnect_attempts, pid, attempts + 1)
      new_backoff = Map.put(state.backoff, pid, backoff)

      new_state = %{state |
        reconnect_attempts: new_attempts,
        backoff: new_backoff
      }

      stats = %{new_state.stats | failures: new_state.stats.failures + 1}
      {:noreply, %{new_state | stats: stats}}
    else
      Logger.error("Worker #{inspect(pid)} failed to reconnect after #{attempts} attempts")

      # Удаляем монитор
      {_ref, new_monitors} = Enum.find(state.monitors, fn {_ref, p} -> p == pid end)
      |> case do
        {ref, _} -> Map.delete(state.monitors, ref)
        nil -> state.monitors
      end

      stats = %{state.stats | failures: state.stats.failures + 1}
      {:noreply, %{state |
        monitors: new_monitors,
        reconnect_attempts: Map.delete(state.reconnect_attempts, pid),
        backoff: Map.delete(state.backoff, pid),
        stats: stats
      }}
    end
  end

  def handle_info({:reconnect, pid}, state) do
    # Пытаемся пересоздать соединение
    case GRPC.Stub.connect("#{state.host}:#{state.port}") do
      {:ok, new_worker} ->
        Logger.info("Successfully reconnected worker for #{state.service}")

        # Обновляем монитор
        ref = Process.monitor(new_worker)
        new_monitors = Map.put(state.monitors, ref, new_worker)

        # Удаляем старые записи
        new_attempts = Map.delete(state.reconnect_attempts, pid)
        new_backoff = Map.delete(state.backoff, pid)

        stats = %{state.stats | reconnects: state.stats.reconnects + 1}

        {:noreply, %{state |
          monitors: new_monitors,
          reconnect_attempts: new_attempts,
          backoff: new_backoff,
          stats: stats
        }}

      {:error, reason} ->
        Logger.error("Failed to reconnect worker for #{state.service}: #{reason}")

        # Пробуем снова через увеличенный backoff
        attempts = Map.get(state.reconnect_attempts, pid, 0)
        if attempts < state.config.max_reconnects do
          backoff = state.config.reconnect_delay * (2 ** attempts) * 2
          Process.send_after(self(), {:reconnect, pid}, backoff)
        end

        {:noreply, state}
    end
  end

  def handle_info(:health_check, state) do
    new_state = check_pool_health(state)
    schedule_health_check()
    {:noreply, new_state}
  end

  def handle_info(:collect_metrics, state) do
    collect_pool_metrics(state)
    schedule_metrics()
    {:noreply, state}
  end

  def handle_info(:cleanup, state) do
    cleanup(self())
    schedule_cleanup()
    {:noreply, state}
  end

  def terminate(_reason, state) do
    Logger.info("Shutting down connection pool for #{state.service}")

    # Очищаем кэш
    :ets.delete(:grpc_channel_cache)

    # Останавливаем пул
    :poolboy.stop(state.pool)

    :ok
  end

  # Приватные функции

  defp pool_config(size, service_name, opts) do
    [
      {:name, {:local, pool_name(service_name)}},
      {:worker_module, GRPC.Stub},
      {:size, size},
      {:max_overflow, Keyword.get(opts, :max_overflow, 2)},
      {:strategy, Keyword.get(opts, :strategy, :fifo)},
      {:auto_ack, false}
    ]
  end

  defp pool_name(service_name) do
    String.to_atom("grpc_pool_#{service_name}")
  end

  defp do_transaction(service_name, fun, timeout, 0) do
    case checkout(service_name, timeout) do
      {:ok, worker} ->
        try do
          fun.(worker)
        after
          checkin(service_name, worker)
        end
      error -> error
    end
  end

  defp do_transaction(service_name, fun, timeout, retries) do
    case do_transaction(service_name, fun, timeout, 0) do
      {:error, reason} when reason in [:no_available_channels, :timeout] ->
        Logger.warning("Transaction failed, #{retries-1} retries left: #{reason}")
        backoff = calculate_backoff(retries)
        :timer.sleep(backoff)
        do_transaction(service_name, fun, timeout, retries - 1)
      result -> result
    end
  end

  defp reconnect_worker(pid, state) do
    # Принудительное переподключение воркера
    send(self(), {:EXIT, pid, :reconnect})
  end

  defp check_pool_health(state) do
    case :poolboy.status(state.pool) do
      {available, overflow, workers} ->
        total = available + overflow + workers

        # Проверяем, что все воркеры живы
        dead_workers = Enum.filter(state.monitors, fn {_ref, pid} ->
          not Process.alive?(pid)
        end)

        if dead_workers != [] do
          Logger.warning("Found #{length(dead_workers)} dead workers in pool for #{state.service}")

          # Очищаем мёртвые воркеры
          {refs, _} = Enum.unzip(dead_workers)
          new_monitors = Map.drop(state.monitors, refs)

          stats = %{state.stats |
            last_health_check: System.system_time(:millisecond),
            failures: state.stats.failures + length(dead_workers)
          }

          %{state | monitors: new_monitors, stats: stats}
        else
          stats = %{state.stats | last_health_check: System.system_time(:millisecond)}
          %{state | stats: stats}
        end

      other ->
        Logger.warning("Pool health check failed for #{state.service}: #{inspect(other)}")
        stats = %{state.stats | failures: state.stats.failures + 1}
        %{state | stats: stats}
    end
  end

  defp collect_pool_metrics(state) do
    {available, overflow, workers} = :poolboy.status(state.pool)
    total = available + overflow + workers

    :telemetry.execute([:music_core, :grpc, :pool], %{
      available: available,
      overflow: overflow,
      workers: workers,
      total: total,
      utilization: if(state.size > 0, do: total / state.size, else: 0),
      size: state.size,
      checked_out: state.stats.checked_out,
      checked_in: state.stats.checked_in,
      failures: state.stats.failures,
      reconnects: state.stats.reconnects,
      dead_workers: length(Enum.reject(state.monitors, fn {_ref, pid} -> Process.alive?(pid) end))
    }, %{
      service: state.service
    })

    :ok
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, 60_000) # Каждую минуту
  end

  defp schedule_metrics do
    Process.send_after(self(), :collect_metrics, 10_000) # Каждые 10 секунд
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 300_000) # Каждые 5 минут
  end

  defp calculate_backoff(attempt) do
    base = 100 * (2 ** attempt)
    jitter = :rand.uniform(base)
    base + jitter
  end
end
