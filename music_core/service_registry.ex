defmodule MusicCore.ServiceRegistry do
  @moduledoc """
  Реестр сервисов для обнаружения и мониторинга компонентов системы.
  """

  use GenServer
  require Logger

  alias ElixirClient.Client.PubSub

  # Клиентский API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def register(service_name, pid, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register, service_name, pid, metadata})
  end

  def unregister(service_name) do
    GenServer.call(__MODULE__, {:unregister, service_name})
  end

  def find(service_name) do
    GenServer.call(__MODULE__, {:find, service_name})
  end

  def find_by_type(service_type) do
    GenServer.call(__MODULE__, {:find_by_type, service_type})
  end

  def list_services do
    GenServer.call(__MODULE__, :list_services)
  end

  def health_check(service_name) do
    GenServer.call(__MODULE__, {:health_check, service_name})
  end

  def subscribe do
    PubSub.subscribe("service_registry")
  end

  def stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Сервер
  def init(opts) do
    state = %{
      services: %{},
      by_type: %{},
      monitors: %{},
      history: :queue.new(),
      stats: %{
        total_registrations: 0,
        total_unregistrations: 0,
        current_services: 0,
        last_change: nil
      }
    }

    schedule_health_check()
    {:ok, state}
  end

  def handle_call({:register, service_name, pid, metadata}, from, state) do
    case Map.get(state.services, service_name) do
      nil ->
        ref = Process.monitor(pid)

        service_info = %{
          name: service_name,
          pid: pid,
          ref: ref,
          type: Map.get(metadata, :type, :unknown),
          metadata: metadata,
          status: :up,
          registered_at: System.system_time(:millisecond),
          last_heartbeat: System.system_time(:millisecond),
          health_status: :unknown
        }

        new_services = Map.put(state.services, service_name, service_info)
        new_monitors = Map.put(state.monitors, ref, service_name)

        type = service_info.type
        current_for_type = Map.get(state.by_type, type, [])
        new_by_type = Map.put(state.by_type, type, [service_name | current_for_type])

        new_stats = %{state.stats |
          total_registrations: state.stats.total_registrations + 1,
          current_services: state.stats.current_services + 1,
          last_change: System.system_time(:millisecond)
        }

        new_history = add_to_history(state.history, {:registered, service_name, pid})

        new_state = %{state |
          services: new_services,
          monitors: new_monitors,
          by_type: new_by_type,
          history: new_history,
          stats: new_stats
        }

        broadcast({:service_registered, service_name, type})

        Logger.info("Service registered: #{service_name} (#{type}) with PID #{inspect(pid)}")
        {:reply, {:ok, service_info}, new_state}

      %{pid: existing_pid} when existing_pid != pid ->
        Logger.warning("Service name #{service_name} already taken by #{inspect(existing_pid)}")
        {:reply, {:error, :name_taken}, state}

      %{pid: existing_pid} when existing_pid == pid ->
        Logger.debug("Service #{service_name} re-registered")
        {:reply, {:ok, Map.get(state.services, service_name)}, state}
    end
  end

  def handle_call({:unregister, service_name}, from, state) do
    case Map.get(state.services, service_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      service_info ->
        new_services = Map.delete(state.services, service_name)
        new_monitors = Map.delete(state.monitors, service_info.ref)

        type = service_info.type
        current_for_type = Map.get(state.by_type, type, [])
        new_for_type = List.delete(current_for_type, service_name)
        new_by_type = if new_for_type == [] do
          Map.delete(state.by_type, type)
        else
          Map.put(state.by_type, type, new_for_type)
        end

        new_stats = %{state.stats |
          total_unregistrations: state.stats.total_unregistrations + 1,
          current_services: state.stats.current_services - 1,
          last_change: System.system_time(:millisecond)
        }

        new_history = add_to_history(state.history, {:unregistered, service_name})

        new_state = %{state |
          services: new_services,
          monitors: new_monitors,
          by_type: new_by_type,
          history: new_history,
          stats: new_stats
        }

        broadcast({:service_unregistered, service_name, type})

        Logger.info("Service unregistered: #{service_name}")
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:find, service_name}, from, state) do
    case Map.get(state.services, service_name) do
      nil -> {:reply, {:error, :not_found}, state}
      service_info -> {:reply, {:ok, service_info}, state}
    end
  end

  def handle_call({:find_by_type, service_type}, from, state) do
    names = Map.get(state.by_type, service_type, [])
    services = Enum.map(names, fn name -> Map.get(state.services, name) end)
    {:reply, {:ok, services}, state}
  end

  def handle_call(:list_services, from, state) do
    services = Enum.map(state.services, fn {name, info} ->
      %{
        name: name,
        pid: info.pid,
        type: info.type,
        status: info.status,
        uptime: System.system_time(:millisecond) - info.registered_at,
        health: info.health_status
      }
    end)

    {:reply, services, state}
  end

  def handle_call({:health_check, service_name}, from, state) do
    case Map.get(state.services, service_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      service_info ->
        health = check_service_health(service_info)
        updated_info = %{service_info | health_status: health}
        new_services = Map.put(state.services, service_name, updated_info)

        {:reply, {:ok, health}, %{state | services: new_services}}
    end
  end

  def handle_call(:get_stats, from, state) do
    stats = %{
      total: state.stats,
      by_type: Enum.map(state.by_type, fn {type, names} -> {type, length(names)} end) |> Enum.into(%{}),
      health: count_health_status(state.services)
    }

    {:reply, stats, state}
  end

  # Обработка сообщений
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}

      service_name ->
        Logger.warning("Service #{service_name} crashed: #{inspect(reason)}")
        new_state = unregister_service(service_name, state)
        {:noreply, new_state}
    end
  end

  def handle_info(:perform_health_checks, state) do
    new_state = perform_all_health_checks(state)
    schedule_health_check()
    {:noreply, new_state}
  end

  # Приватные функции
  defp unregister_service(service_name, state) do
    case Map.get(state.services, service_name) do
      nil -> state
      service_info ->
        new_services = Map.delete(state.services, service_name)
        new_monitors = Map.delete(state.monitors, service_info.ref)

        type = service_info.type
        current_for_type = Map.get(state.by_type, type, [])
        new_for_type = List.delete(current_for_type, service_name)
        new_by_type = if new_for_type == [] do
          Map.delete(state.by_type, type)
        else
          Map.put(state.by_type, type, new_for_type)
        end

        new_stats = %{state.stats |
          total_unregistrations: state.stats.total_unregistrations + 1,
          current_services: state.stats.current_services - 1,
          last_change: System.system_time(:millisecond)
        }

        new_history = add_to_history(state.history, {:unregistered, service_name})

        broadcast({:service_unregistered, service_name, type})

        %{state |
          services: new_services,
          monitors: new_monitors,
          by_type: new_by_type,
          history: new_history,
          stats: new_stats
        }
    end
  end

  defp schedule_health_check do
    Process.send_after(self(), :perform_health_checks, 30_000)
  end

  defp check_service_health(service_info) do
    if Process.alive?(service_info.pid) do
      try do
        case GenServer.call(service_info.pid, :ping, 1000) do
          :pong -> :healthy
          other -> :unhealthy
        end
      catch
        :exit, reason -> :unreachable
      end
    else
      :dead
    end
  end

  defp perform_all_health_checks(state) do
    new_services = Enum.reduce(state.services, %{}, fn {name, info}, acc ->
      health = check_service_health(info)
      updated_info = %{info | health_status: health}
      Map.put(acc, name, updated_info)
    end)

    Enum.each(new_services, fn {name, info} ->
      if info.health_status != :healthy do
        Logger.warning("Service #{name} health: #{info.health_status}")
      end
    end)

    %{state | services: new_services}
  end

  defp add_to_history(queue, event) do
    new_queue = :queue.in({System.system_time(:millisecond), event}, queue)

    if :queue.len(new_queue) > 100 do
      {{:value, oldest}, trimmed} = :queue.out(new_queue)
      trimmed
    else
      new_queue
    end
  end

  defp broadcast(message) do
    PubSub.broadcast("service_registry", message)
  end

  defp count_health_status(services) do
    Enum.reduce(services, %{healthy: 0, unhealthy: 0, dead: 0, unknown: 0}, fn {_name, info}, acc ->
      key = case info.health_status do
        :healthy -> :healthy
        :unhealthy -> :unhealthy
        :dead -> :dead
        other -> :unknown
      end
      Map.update(acc, key, 1, fn val -> val + 1 end)
    end)
  end
end
