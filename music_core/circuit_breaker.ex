defmodule MusicCore.CircuitBreaker do
  @moduledoc """
  Circuit breaker для защиты от каскадных отказов.
  """

  use GenServer
  require Logger

  alias MusicCore.AudioStreaming.Processor

  # Клиентский API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def open?(circuit_name) do
    GenServer.call(__MODULE__, {:open?, circuit_name})
  end

  def trip(circuit_name) do
    GenServer.cast(__MODULE__, {:trip, circuit_name})
  end

  def reset(circuit_name) do
    GenServer.cast(__MODULE__, {:reset, circuit_name})
  end

  def status_all do
    GenServer.call(__MODULE__, :status_all)
  end

  def health_check do
    case Process.whereis(__MODULE__) do
      nil -> :unhealthy
      pid ->
        case GenServer.call(__MODULE__, :health_check_ping, 1000) do
          :pong -> :healthy
          _ -> :unhealthy
        end
    end
  end

  # Сервер
  def init(opts) do
    state = %{
      timers: %{},
      circuits: %{
        discord_streaming: %{
          state: :closed,
          failure_count: 0,
          last_failure: nil,
          open_until: nil
        },
        database: %{
          state: :closed,
          failure_count: 0,
          last_failure: nil,
          open_until: nil
        },
        cache: %{
          state: :closed,
          failure_count: 0,
          last_failure: nil,
          open_until: nil
        }
      },
      config: %{
        failure_threshold: 5,
        timeout_ms: 30_000,
        half_open_timeout: 5_000
      }
    }

    {:ok, state}
  end

  def handle_call({:open?, circuit_name}, state) do
    circuit = Map.get(state.circuits, circuit_name)

    is_open = case circuit do
      nil -> false
      %{state: :open, open_until: until_time} ->
        if System.system_time(:millisecond) > until_time do
          send(self(), {:half_open, circuit_name})
          false
        else
          true
        end
      %{state: :half_open} -> false
      _ -> false
    end

    {:reply, is_open, state}
  end

  def handle_call(:status_all, state) do
    status = Enum.map(state.circuits, fn {name, data} ->
      {name, Map.take(data, [:state, :failure_count])}
    end) |> Enum.into(%{})

    {:reply, status, state}
  end

  def handle_call(:health_check_ping, state) do
    {:reply, :pong, state}
  end

  def handle_cast({:trip, circuit_name}, state) do
    circuit = Map.get(state.circuits, circuit_name)

    if circuit do
      failure_count = circuit.failure_count + 1
      threshold = state.config.failure_threshold

      new_circuit = if failure_count >= threshold do
        %{circuit |
          state: :open,
          failure_count: failure_count,
          last_failure: System.system_time(:millisecond),
          open_until: System.system_time(:millisecond) + state.config.timeout_ms
        }
      else
        %{circuit |
          failure_count: failure_count,
          last_failure: System.system_time(:millisecond)
        }
      end

      new_circuits = Map.put(state.circuits, circuit_name, new_circuit)
      {:noreply, %{state | circuits: new_circuits}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:reset, circuit_name}, state) do
    circuit = Map.get(state.circuits, circuit_name)

    if circuit do
      case Map.get(state.timers, circuit_name) do
        nil -> :ok
        tref -> Process.cancel_timer(tref)
      end

      new_circuit = %{circuit |
        state: :closed,
        failure_count: 0,
        last_failure: nil,
        open_until: nil
      }
      new_circuits = Map.put(state.circuits, circuit_name, new_circuit)
      new_timers = Map.delete(state.timers, circuit_name)

      {:noreply, %{state |
        circuits: new_circuits,
        timers: new_timers
      }}
    else
      {:noreply, state}
    end
  end

  def handle_info({:half_open, circuit_name}, state) do
    circuit = Map.get(state.circuits, circuit_name)

    if circuit && circuit.state == :open do
      new_circuit = %{circuit |
        state: :half_open,
        open_until: nil
      }
      new_circuits = Map.put(state.circuits, circuit_name, new_circuit)
      tref = Process.send_after(self(), {:check_half_open, circuit_name}, state.config.half_open_timeout)
      new_timers = Map.put(state.timers, circuit_name, tref)

      {:noreply, %{state |
        circuits: new_circuits,
        timers: new_timers
      }}
    else
      {:noreply, state}
    end
  end

  def handle_info({:check_half_open, circuit_name}, state) do
    circuit = Map.get(state.circuits, circuit_name)

    if circuit && circuit.state == :half_open do
      new_circuit = %{circuit |
        state: :closed,
        failure_count: 0
      }
      new_circuits = Map.put(state.circuits, circuit_name, new_circuit)
      new_timers = Map.delete(state.timers, circuit_name)

      {:noreply, %{state |
        circuits: new_circuits,
        timers: new_timers
      }}
    else
      new_timers = Map.delete(state.timers, circuit_name)
      {:noreply, %{state | timers: new_timers}}
    end
  end

  def terminate(reason, state) do
    Logger.info("CircuitBreaker terminating: #{inspect(reason)}")

    Enum.each(state.timers, fn tref ->
      Process.cancel_timer(tref)
    end)

    :ok
  end
end
