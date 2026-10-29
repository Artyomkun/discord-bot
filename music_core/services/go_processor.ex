defmodule MusicCore.Services.GoProcessor do
  @moduledoc """
  GenServer для управления Go аудио процессором.

  Отвечает за:
  - Запуск и остановку Go-процесса
  - Мониторинг здоровья
  - Переподключение при сбоях
  - Кэширование соединений
  """

  use GenServer
  require Logger

  alias MusicCore.GoProcessor.Client
  alias MusicCore.Metrics

  # API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Получить статус Go процессора.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @doc """
  Принудительно перезапустить Go процессор.
  """
  def restart do
    GenServer.cast(__MODULE__, :restart)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      opts: opts,
      go_port: nil,
      port_ref: nil,
      healthy: false,
      go_running: false,
      go_health_check_attempts: 0,
      last_check: nil,
      restart_count: 0,
      max_restarts: Keyword.get(opts, :max_restarts, 5),
      restart_window: Keyword.get(opts, :restart_window, 60_000),
      restart_history: []
    }

    Logger.info("🚀 Starting GoProcessor...")

    case start_go_process(state) do
      {:ok, new_state} ->
        schedule_health_check()
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to start GoProcessor: #{reason}")
        {:ok, state}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      healthy: state.healthy,
      port: state.go_port,
      port_ref: state.port_ref,
      go_running: state.go_running,
      last_check: state.last_check,
      restart_count: state.restart_count,
      uuptime: (if state.port_ref, do: Process.info(state.port_ref, :total_heap_size), else: nil)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_cast(:restart, state) do
    Logger.warning("Manually restarting GoProcessor...")
    stop_go_process(state)

    case start_go_process(state) do
      {:ok, new_state} ->
        {:noreply, new_state}
      {:error, reason} ->
        Logger.error("Manual restart failed: #{reason}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:health_check, state) do
    healthy = Client.health_check()
    new_state = %{state | healthy: healthy, last_check: DateTime.utc_now()}

    if healthy do
      Logger.debug("GoProcessor health check passed")
    else
      Logger.warning("GoProcessor health check failed")
      if state.port_ref && !Process.alive?(state.port_ref) do
        Logger.error("GoProcessor process died, restarting...")
        {:noreply, new_state}
        |> restart_if_needed()
      end
    end

    Metrics.gauge("go_processor.healthy", if(healthy, do: 1, else: 0))

    schedule_health_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_go_health, state) do
    case check_go_health(state.go_port) do
      {:ok, _} ->
        Logger.info("Go processor health check passed")
        {:noreply, %{state | go_running: true, go_health_check_attempts: 0}}

      {:error, reason} ->
        attempts = state.go_health_check_attempts + 1
        Logger.warning("Go processor health check failed (attempt #{attempts}): #{reason}")

        if attempts >= 3 do
          Logger.error("Go processor health check failed after 3 attempts, restarting")
          {:noreply, restart_go_process(state)}
        else
          Process.send_after(self(), :check_go_health, 1000)
          {:noreply, %{state | go_health_check_attempts: attempts}}
        end
    end
  end

  @impl true
  def handle_info({:go_process, :started, port}, state) do
    Logger.info("GoProcessor started on port #{port}")
    {:noreply, %{state | go_port: port, go_running: true}}
  end

  @impl true
  def handle_info({:go_process, :stopped, reason}, state) do
    Logger.warning("GoProcessor stopped: #{reason}")
    new_state = %{state | go_port: nil, go_running: false, healthy: false}
    {:noreply, new_state}
    |> restart_if_needed()
  end

  @impl true
  def handle_info({:go_process, :error, error}, state) do
    Logger.error("GoProcessor error: #{error}")
    {:noreply, %{state | healthy: false}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Stopping GoProcessor: #{inspect(reason)}")
    stop_go_process(state)
    :ok
  end

  # Private Functions

  defp start_go_process(state) do
    if rate_limited?(state) do
      Logger.error("Too many restarts, backing off...")
      {:error, "rate_limited"}
    else
      do_start_go_process(state)
    end
  end

  defp do_start_go_process(state) do
    go_bin = Keyword.get(state.opts, :go_bin, "go")
    app_path = Keyword.get(state.opts, :app_path, "go_processor/build")
    start_port = Keyword.get(state.opts, :go_port, 8082)

    case System.find_executable(go_bin) do
      nil ->
        Logger.error("Go executable not found: #{go_bin}")
        {:error, "go_not_found"}

      _go_path ->
        main_go = Path.join([app_path, "main.go"])
        unless File.exists?(main_go) do
          Logger.error("main.go not found at #{main_go}")
          {:error, "main_go_not_found"}
        end

        case find_available_port(start_port) do
          nil ->
            Logger.error("No available port found starting from #{start_port}")
            {:error, "no_available_port"}

          port ->
            cmd = "cd #{app_path} && #{go_bin} run main.go --port #{port}"
            Logger.info("Starting Go processor: #{cmd}")

            port_cmd = String.to_charlist(cmd)
            case :erlang.open_port({:spawn, port_cmd}, [:binary, :exit_status, :stderr_to_stdout]) do
              port_ref when is_port(port_ref) ->
                Process.send_after(self(), :check_go_health, 3000)

                new_history = [DateTime.utc_now() | state.restart_history]
                new_restart_count = state.restart_count + 1

                new_state = %{
                  state
                  | port_ref: port_ref,
                    go_port: port,
                    go_running: false,
                    go_health_check_attempts: 0,
                    restart_history: new_history,
                    restart_count: new_restart_count
                }

                {:ok, new_state}

              error ->
                Logger.error("Failed to spawn Go process: #{inspect(error)}")
                {:error, "spawn_failed"}
            end
        end
    end
  end

  defp find_available_port(start_port, max_attempts \\ 100) do
    Enum.find_value(start_port..(start_port + max_attempts), fn port ->
      case :gen_tcp.listen(port, [:binary, {:packet, 0}, {:reuseaddr, true}]) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          port
        {:error, _} ->
          false
      end
    end)
  end

  defp check_go_health(port) when is_integer(port) do
    url = "http://localhost:#{port}/health"
    headers = []

    case :httpc.request(:get, {String.to_charlist(url), headers}, [{:timeout, 2000}], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        {:ok, body}
      {:ok, {{_, status, _}, _, _}} ->
        {:error, "HTTP #{status}"}
      {:error, reason} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  defp restart_go_process(state) do
    if state.port_ref do
      :erlang.port_close(state.port_ref)
    end

    case start_go_process(state) do
      {:ok, new_state} -> new_state
      {:error, _} -> state
    end
  end

  defp stop_go_process(state) do
    if state.port_ref && is_port(state.port_ref) do
      :erlang.port_close(state.port_ref)
    end
    :ok
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, 10_000)
  end

  defp rate_limited?(state) do
    now = DateTime.utc_now()
    window_start = DateTime.add(now, -state.restart_window, :millisecond)

    recent = Enum.filter(state.restart_history, fn dt ->
      DateTime.compare(dt, window_start) == :gt
    end)

    length(recent) >= state.max_restarts
  end

  defp restart_if_needed({:noreply, state}) do
    if rate_limited?(state) do
      Logger.error("Rate limited — not restarting")
      {:noreply, state}
    else
      Logger.info("Restarting GoProcessor...")
      case start_go_process(state) do
        {:ok, new_state} -> {:noreply, new_state}
        {:error, _reason} -> {:noreply, state}
      end
    end
  end

  @doc """
  Нормализация аудио через Go сервис.
  """
  def normalize_audio(audio_stream, target_peak, mode, opts \\ []) do
    Client.normalize(audio_stream, target_peak, mode)
  end
end
