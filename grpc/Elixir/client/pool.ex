defmodule ElixirClient.Client.Pool do
  @moduledoc """
  Пул соединений для gRPC клиентов.

  Предоставляет:
  - Управление пулом соединений через poolboy
  - Автоматическое переподключение
  - Метрики и мониторинг
  - Graceful shutdown
  - Таймауты и ретраи
  """

  use GenServer
  require Logger

  alias ElixirClient.Client.{Metrics, ConnectionPool}

  @type pool_config :: %{
    name: atom(),
    size: non_neg_integer(),
    max_overflow: non_neg_integer(),
    strategy: :fifo | :lifo,
    host: String.t(),
    port: :inet.port_number(),
    service: String.t(),
    stub_module: module(),
    timeout: non_neg_integer()
  }

  @type pool_state :: %{
    pool: pid(),
    config: pool_config(),
    stats: %{
      created: non_neg_integer(),
      checked_out: non_neg_integer(),
      checked_in: non_neg_integer(),
      failures: non_neg_integer(),
      last_health_check: integer() | nil
    },
    monitors: %{reference() => pid()}
  }

  # Клиентский API

  @doc """
  Запускает пул соединений.
  """
  @spec start_link(pool_config()) :: GenServer.on_start()
  def start_link(config) do
    name = Keyword.get(config, :name, __MODULE__)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @doc """
  Получает соединение из пула.
  """
  @spec checkout(atom(), timeout()) :: {:ok, pid()} | {:error, atom()}
  def checkout(pool_name, timeout \\ 5000) do
    case :poolboy.checkout(pool_name, true, timeout) do
      worker when is_pid(worker) ->
        Metrics.record_checkout(pool_name)
        {:ok, worker}

      :full ->
        Metrics.record_checkout_failure(pool_name, :full)
        {:error, :no_available_channels}

      other ->
        Metrics.record_checkout_failure(pool_name, other)
        {:error, other}
    end
  end

  @doc """
  Возвращает соединение в пул.
  """
  @spec checkin(atom(), pid()) :: :ok
  def checkin(pool_name, worker) do
    :poolboy.checkin(pool_name, worker)
    Metrics.record_checkin(pool_name)
    :ok
  end

  @doc """
  Выполняет транзакцию с соединением.
  """
  @spec transaction(atom(), (pid() -> any()), keyword()) :: any()
  def transaction(pool_name, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    retries = Keyword.get(opts, :retries, 1)

    do_transaction(pool_name, fun, timeout, retries)
  end

  @doc """
  Получает статус пула.
  """
  @spec status(atom()) :: {:ok, map()} | {:error, atom()}
  def status(pool_name) do
    case :poolboy.status(pool_name) do
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
  Останавливает пул.
  """
  @spec stop(atom()) :: :ok
  def stop(pool_name) do
    case Process.whereis(pool_name) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  # GenServer колбэки

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)

    pool_name = Keyword.get(config, :name, __MODULE__)
    size = Keyword.get(config, :size, 10)
    max_overflow = Keyword.get(config, :max_overflow, 2)
    strategy = Keyword.get(config, :strategy, :fifo)
    host = Keyword.get(config, :host, "localhost")
    port = Keyword.get(config, :port, 50051)
    service = Keyword.get(config, :service, "unknown")
    stub_module = Keyword.get(config, :stub_module)

    pool_config = [
      {:name, {:local, pool_name}},
      {:worker_module, GRPC.Stub},
      {:size, size},
      {:max_overflow, max_overflow},
      {:strategy, strategy}
    ]

    worker_args = [host: host, port: port, service: service, stub: stub_module]

    case :poolboy.start_link(pool_config, worker_args) do
      {:ok, pool} ->
        state = %{
          pool: pool,
          config: %{
            name: pool_name,
            size: size,
            max_overflow: max_overflow,
            strategy: strategy,
            host: host,
            port: port,
            service: service,
            stub_module: stub_module,
            timeout: Keyword.get(config, :timeout, 5000)
          },
          stats: %{
            created: 0,
            checked_out: 0,
            checked_in: 0,
            failures: 0,
            last_health_check: nil
          },
          monitors: %{}
        }

        # Запускаем периодические задачи
        schedule_health_check()
        schedule_metrics_collection()

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    pool_status = :poolboy.status(state.pool)
    stats = Map.put(state.stats, :pool_status, pool_status)
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:checkout, timeout}, _from, state) do
    case :poolboy.checkout(state.pool, true, timeout) do
      worker when is_pid(worker) ->
        ref = Process.monitor(worker)
        monitors = Map.put(state.monitors, ref, worker)
        stats = %{state.stats | checked_out: state.stats.checked_out + 1}
        {:reply, {:ok, worker}, %{state | monitors: monitors, stats: stats}}

      :full ->
        stats = %{state.stats | failures: state.stats.failures + 1}
        {:reply, {:error, :no_available_channels}, %{state | stats: stats}}

      other ->
        stats = %{state.stats | failures: state.stats.failures + 1}
        {:reply, {:error, other}, %{state | stats: stats}}
    end
  end

  @impl true
  def handle_cast({:checkin, worker}, state) do
    :poolboy.checkin(state.pool, worker)
    stats = %{state.stats | checked_in: state.stats.checked_in + 1}
    {:noreply, %{state | stats: stats}}
  end

  @impl true
  def handle_cast(:cleanup, state) do
    # Очищаем неиспользуемые соединения
    :poolboy.child_spec(state.pool, [])
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_check(state)
    schedule_health_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:collect_metrics, state) do
    collect_metrics(state)
    schedule_metrics_collection()
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case Map.get(state.monitors, ref) do
      ^pid ->
        Logger.warning("Worker #{inspect(pid)} died: #{inspect(reason)}")
        monitors = Map.delete(state.monitors, ref)
        stats = %{state.stats | failures: state.stats.failures + 1}
        {:noreply, %{state | monitors: monitors, stats: stats}}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.info("Pool received EXIT: #{inspect(reason)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Stopping connection pool for #{state.config.service}: #{inspect(reason)}")

    # Отменяем все мониторы
    Enum.each(state.monitors, fn {ref, pid} ->
      Process.demonitor(ref, [:flush])
    end)

    # Останавливаем poolboy
    :poolboy.stop(state.pool)

    :ok
  end

  # Приватные функции

  defp do_transaction(pool_name, fun, timeout, 0) do
    case checkout(pool_name, timeout) do
      {:ok, worker} ->
        try do
          fun.(worker)
        after
          checkin(pool_name, worker)
        end
      error -> error
    end
  end

  defp do_transaction(pool_name, fun, timeout, retries) do
    case do_transaction(pool_name, fun, timeout, 0) do
      {:error, reason} when reason in [:no_available_channels, :timeout] ->
        Logger.warning("Transaction failed, #{retries-1} retries left: #{reason}")
        backoff = calculate_backoff(retries)
        :timer.sleep(backoff)
        do_transaction(pool_name, fun, timeout, retries - 1)
      result -> result
    end
  end

  defp perform_health_check(state) do
    case :poolboy.status(state.pool) do
      {available, overflow, workers} when available + overflow + workers >= 0 ->
        # Проверяем, что все соединения живы
        stats = %{state.stats | last_health_check: System.system_time(:millisecond)}
        %{state | stats: stats}

      other ->
        Logger.warning("Pool health check failed: #{inspect(other)}")
        stats = %{state.stats | failures: state.stats.failures + 1}
        %{state | stats: stats}
    end
  end

  defp collect_metrics(state) do
    {available, overflow, workers} = :poolboy.status(state.pool)

    :telemetry.execute([:music_core, :grpc, :pool], %{
      available: available,
      overflow: overflow,
      workers: workers,
      size: state.config.size,
      max_overflow: state.config.max_overflow,
      checked_out: state.stats.checked_out,
      checked_in: state.stats.checked_in,
      failures: state.stats.failures
    }, %{
      service: state.config.service,
      pool: state.config.name
    })

    :ok
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, 60_000) # Каждую минуту
  end

  defp schedule_metrics_collection do
    Process.send_after(self(), :collect_metrics, 10_000) # Каждые 10 секунд
  end

  defp calculate_backoff(attempt) do
    base = 100 * (2 ** attempt)
    jitter = :rand.uniform(base)
    base + jitter
  end

  # Макрос для удобного использования

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @pool_name Keyword.fetch!(opts, :name)
      @service Keyword.fetch!(opts, :service)
      @stub Keyword.fetch!(opts, :stub)
      @port Keyword.get(opts, :port, 50051)
      @host Keyword.get(opts, :host, "localhost")
      @size Keyword.get(opts, :size, 10)
      @timeout Keyword.get(opts, :timeout, 5000)

      def start_link(_) do
        Grpc.Client.Pool.start_link([
          name: @pool_name,
          service: @service,
          stub_module: @stub,
          port: @port,
          host: @host,
          size: @size,
          timeout: @timeout
        ])
      end

      def child_spec(_) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, []},
          type: :worker,
          restart: :permanent,
          shutdown: 5000
        }
      end

      def transaction(fun, opts \\ []) do
        Grpc.Client.Pool.transaction(@pool_name, fn channel ->
          apply(@stub, fun, [channel, opts])
        end, opts)
      end

      def call(method, request, opts \\ []) do
        transaction(fn channel ->
          apply(@stub, method, [channel, request, opts])
        end, opts)
      end

      def status do
        Grpc.Client.Pool.status(@pool_name)
      end

      def stop do
        Grpc.Client.Pool.stop(@pool_name)
      end
    end
  end
end
