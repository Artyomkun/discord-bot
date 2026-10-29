defmodule MusicCore.WebSocket.Handler do
  @moduledoc """
  Обработчик WebSocket соединений.
  """

  @behaviour WebSock

  require Logger
  use GenServer

  alias MusicCore.{QueueManager, Metrics, Cache}
  alias MusicCore.AudioEffects.Effects
  alias MusicCore.AudioStreaming.Processor
  alias MusicCore.AudioStream.Manager

  @impl true
  def init(opts) do
    client_id = generate_client_id()

    state = %{
      client_id: client_id,
      authenticated: false,
      client_type: nil,
      subscribed_events: [],
      heartbeat_timer: nil,
      connected_at: DateTime.utc_now()
    }

    timer = Process.send_after(self(), :heartbeat, 30_000)

    Logger.info("WebSocket client connected: #{client_id}")

    Metrics.record(:websocket_connected, 1, %{client_id: client_id})

    {:ok, %{state | heartbeat_timer: timer}}
  end

  def set_client_type(pid, type) when type in [:go, :java] do
    GenServer.call(pid, {:set_client_type, type})
  end

  @impl true
  def handle_call({:set_client_type, type}, _from, state) do
    Logger.info("Client #{state.client_id} authenticated as #{type}")
    {:reply, :ok, %{state | client_type: type, authenticated: true}}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    heartbeat_msg = Jason.encode!(%{type: "heartbeat", timestamp: DateTime.utc_now()})
    timer = Process.send_after(self(), :heartbeat, 30_000)

    {:push, {:text, heartbeat_msg}, %{state | heartbeat_timer: timer}}
  end

  @impl true
  def handle_info({:broadcast, event, data}, state) do
    if event in state.subscribed_events or Enum.member?(state.subscribed_events, "*") do
      message = Jason.encode!(%{type: "event", event: event, data: data})
      {:push, {:text, message}, state}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_in({text, opcode: :text}, state) do
    case Jason.decode(text) do
      {:ok, message} ->
        handle_message(message, state)

      {:error, reason} ->
        Logger.warning("Invalid JSON received: #{inspect(reason)}")
        Metrics.record(:websocket_invalid_json, 1, %{client_id: state.client_id, error: reason})

        {:reply, {:text, Jason.encode!(%{error: "Invalid JSON"})}, state}
    end
  end

  @impl true
  def handle_in({_data, opcode: _}, state) do
    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("WebSocket client disconnected: #{state.client_id}, reason: #{inspect(reason)}")

    Metrics.record(:websocket_disconnected, 1, %{client_id: state.client_id, reason: inspect(reason)})

    if state.heartbeat_timer do
      Process.cancel_timer(state.heartbeat_timer)
    end

    :ok
  end

  # Приватные функции

  defp handle_message(%{"type" => "auth", "token" => token, "client_type" => client_type}, state) do
    case authenticate_client(token, client_type) do
      {:ok, client_info} ->
        new_state = %{state |
          authenticated: true,
          client_type: client_type
        }

        Metrics.record(:websocket_authenticated, 1, %{client_id: state.client_id, client_type: client_type})

        response = %{
          type: "auth_success",
          client_id: state.client_id,
          client_info: client_info
        }

        {:reply, {:text, Jason.encode!(response)}, new_state}

      {:error, reason} ->
        Metrics.record(:websocket_auth_failed, 1, %{client_id: state.client_id, error: reason})

        response = %{type: "auth_failed", error: reason}
        {:reply, {:text, Jason.encode!(response)}, state}
    end
  end

  defp handle_message(%{"type" => "subscribe", "events" => events}, state) do
    if state.authenticated do
      new_state = %{state | subscribed_events: events}

      Metrics.record(:websocket_subscribed, length(events), %{client_id: state.client_id, events: events})

      response = %{type: "subscribed", events: events}
      {:reply, {:text, Jason.encode!(response)}, new_state}
    else
      response = %{type: "error", message: "Not authenticated"}
      {:reply, {:text, Jason.encode!(response)}, state}
    end
  end

  defp handle_message(%{"type" => "audio_process", "stream_id" => stream_id, "data" => data, "effects" => effects}, state) do
    if state.authenticated do
      Metrics.record(:audio_processing_start, 1, %{stream_id: stream_id, client_type: state.client_type})

      case Processor.process_audio(stream_id, data, effects) do
        {:ok, processed_data} ->
          Metrics.record(:audio_processing_stop, 1, %{stream_id: stream_id, client_type: state.client_type})

          response = %{
            type: "audio_processed",
            stream_id: stream_id,
            data: processed_data
          }

          {:reply, {:text, Jason.encode!(response)}, state}

        {:queued, stream_id} ->
          response = %{
            type: "audio_queued",
            stream_id: stream_id,
            message: "Processing queued"
          }

          {:reply, {:text, Jason.encode!(response)}, state}

        {:error, reason} ->
          Metrics.record(:audio_processing_error, 1, %{stream_id: stream_id, client_type: state.client_type, error: reason})

          response = %{type: "error", message: "Audio processing failed", reason: reason}
          {:reply, {:text, Jason.encode!(response)}, state}
      end
    else
      response = %{type: "error", message: "Not authenticated"}
      {:reply, {:text, Jason.encode!(response)}, state}
    end
  end

  defp handle_message(%{"type" => "queue_manage", "guild_id" => guild_id, "action" => action, "track" => track}, state) do
    if state.authenticated do
      case QueueManager.manage_queue(guild_id, action, track) do
        {:ok, result} ->
          Metrics.record(:websocket_queue_action, 1, %{client_id: state.client_id, action: action})
          response = %{type: "queue_updated", result: result}
          {:reply, {:text, Jason.encode!(response)}, state}

        {:error, reason} ->
          Metrics.record(:websocket_queue_error, 1, %{client_id: state.client_id, action: action, error: reason})
          response = %{type: "error", message: "Queue operation failed", reason: reason}
          {:reply, {:text, Jason.encode!(response)}, state}
      end
    else
      response = %{type: "error", message: "Not authenticated"}
      {:reply, {:text, Jason.encode!(response)}, state}
    end
  end

  defp handle_message(%{"type" => "get_stats"}, state) do
    if state.authenticated do
      stats = %{
        audio_processor: Processor.stats(),
        stream_manager: Manager.get_stats(),
        cache: Cache.stats(:audio_cache),
        effects_cache: Cache.stats(:effects_cache)
      }

      response = %{type: "stats", data: stats}
      {:reply, {:text, Jason.encode!(response)}, state}
    else
      response = %{type: "error", message: "Not authenticated"}
      {:reply, {:text, Jason.encode!(response)}, state}
    end
  end

  defp handle_message(unknown, state) do
    Logger.warning("Unknown message type: #{inspect(unknown)}")
    response = %{type: "error", message: "Unknown message type"}
    {:reply, {:text, Jason.encode!(response)}, state}
  end

  defp authenticate_client(token, client_type) do
    case Application.get_env(:music_core, :api_tokens) do
      tokens when is_map(tokens) ->
        case Map.get(tokens, client_type) do
          ^token -> {:ok, %{type: client_type, authenticated: true}}
          _ -> {:error, "invalid token"}
        end

      _ ->
        {:error, "tokens not configured"}
    end
  end

  defp generate_client_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    "ws_#{timestamp}_#{random}"
  end
end
