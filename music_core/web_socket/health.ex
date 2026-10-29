defmodule MusicCore.WebSocket.Health do
  @moduledoc """
  Health checks для WebSocket и gRPC.
  """

  alias MusicCore.{AudioStreaming.Processor, QueueManager}
  alias MusicCore.WebSocket.Handler

  @doc """
  Проверяет общее состояние системы.
  """
  @spec check() :: :ok | {:error, String.t()}
  def check do
    with :ok <- check_processor(),
          :ok <- check_queues(),
          :ok <- check_connections() do
      :ok
    end
  end

  @doc """
  Проверяет готовность принимать трафик.
  """
  @spec ready?() :: boolean()
  def ready? do
    check() == :ok
  end

  # Приватные проверки

  defp check_processor do
    if Process.whereis(Processor) != nil and Process.alive?(Process.whereis(Processor)) do
      :ok
    else
      {:error, "audio processor not ready"}
    end
  end

  defp check_queues do
    # Проверяем, что QueueManager жив и может ответить
    case Process.whereis(QueueManager) do
      nil ->
        {:error, "queue manager not running"}

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          # Опционально: проверяем размер очереди
          case GenServer.call(QueueManager, :get_queue_status, 1000) do
            {:ok, status} when status.active_tasks < 1000 -> :ok
            {:ok, status} -> {:error, "queue overload: #{status.active_tasks} tasks"}
            _ -> {:error, "queue manager unhealthy"}
          end
        else
          {:error, "queue manager dead"}
        end
    end
  rescue
    _ -> {:error, "queue manager timeout"}
  end

  defp check_connections do
    # Проверяем количество активных WebSocket соединений
    case :pg.get_members(:websocket, Handler) do
      [] -> {:error, "no websocket handlers"}
      members when length(members) > 0 -> :ok
    end
  rescue
    _ -> {:error, "pg not available"}
  end
end
