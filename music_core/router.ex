defmodule MusicCore.Router do
  @moduledoc """
  HTTP роутер для MusicCore API.

  Предоставляет REST API для взаимодействия с внешними сервисами (Go, Java).
  """

  use Plug.Router
  use Plug.ErrorHandler

  require Logger

  alias MusicCore.{Metrics, Cache, QueueManager, Commands}
  alias MusicCore.AudioEffects.Effects
  alias MusicCore.Schema.Report

  plug Plug.Logger
  plug Plug.RequestId
  plug :match
  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  plug :dispatch

  @max_request_size 10_000_000  # 10MB
  @table_name :router_state

  # ========== ИНИЦИАЛИЗАЦИЯ ==========

  def init do
    :ets.new(@table_name, [:named_table, :public, :set])
    :ets.insert(@table_name, {:disabled, false})
    :ets.insert(@table_name, {:active_requests, 0})
  end

  # ========== ROUTES ==========

  # Health check
  get "/health" do
    health_status = get_health_status()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(health_status))
  end

  # API для очередей
  get "/api/queues/:guild_id" do
    guild_id = conn.path_params["guild_id"]

    case QueueManager.get_queue(guild_id) do
      [] ->
        Metrics.record(:api_queue_get, 1, %{guild_id: guild_id})
        send_json(conn, 200, %{queue: []})

      queue_data ->
        Metrics.record(:api_queue_get, 1, %{guild_id: guild_id})
        send_json(conn, 200, %{queue: queue_data})
    end
  end

  post "/api/queues/:guild_id/tracks" do
    guild_id = conn.path_params["guild_id"]
    %{"track" => track} = conn.body_params

    case QueueManager.add_track(guild_id, track, %{}) do
      {:ok, position} ->
        Metrics.record(:api_queue_add, 1, %{guild_id: guild_id})
        send_json(conn, 201, %{status: "added", position: position})

      {:error, reason} ->
        Metrics.error(:api_queue_add_error, reason, %{guild_id: guild_id})
        send_json(conn, 400, %{error: reason})
    end
  end

  delete "/api/queues/:guild_id/tracks" do
    guild_id = conn.path_params["guild_id"]
    %{"track_id" => track_id} = conn.body_params

    # TODO: реализовать удаление конкретного трека
    send_json(conn, 200, %{status: "removed"})
  end

  # API для эффектов
  get "/api/effects/:guild_id" do
    guild_id = conn.path_params["guild_id"]

    case Cache.get(:effects_cache, "effects_#{guild_id}") do
      {:ok, effects} ->
        Metrics.record(:api_effects_get, 1, %{guild_id: guild_id})
        send_json(conn, 200, %{effects: effects})

      {:error, :not_found} ->
        send_json(conn, 200, %{effects: []})
    end
  end

  post "/api/effects/:guild_id" do
    guild_id = conn.path_params["guild_id"]
    %{"effect" => effect} = conn.body_params

    effects_key = "effects_#{guild_id}"
    current_effects = Cache.get(:effects_cache, effects_key, [])
    new_effects = [effect | current_effects]

    Cache.put(:effects_cache, effects_key, new_effects)

    Metrics.record(:effect_applied, 1, %{effect: effect["name"], guild_id: guild_id})

    send_json(conn, 201, %{effect: effect, status: "applied"})
  end

  # API для аудио обработки (для Go/Java сервисов)
  post "/api/audio/process" do
    # Проверяем размер
    content_length = conn
      |> get_req_header("content-length")
      |> List.first()
      |> case do
        nil -> 0
        val -> String.to_integer(val)
      end

    if content_length > @max_request_size do
      send_json(conn, 413, %{error: "Request too large"})
    else
      %{"stream_id" => stream_id, "audio_data" => audio_data, "effects" => effects} = conn.body_params

      Metrics.record(:audio_processing_start, 1, %{stream_id: stream_id, source: "api"})

      audio_binary = case audio_data do
        "data:audio/opus;base64," <> base64 -> Base.decode64!(base64)
        _ -> audio_data
      end

      case Effects.apply_effects(audio_binary, effects, []) do
        {:ok, result} ->
          processed_audio = result.audio
          result_data = Base.encode64(processed_audio)

          response = %{
            stream_id: stream_id,
            status: "processed",
            processed_audio: "data:audio/opus;base64," <> result_data,
            effects_applied: result.metadata.applied_effects,
            processing_time_ms: result.metadata.processing_time,
            cache_hit: result.metadata.cache_hit
          }

          Metrics.record(:audio_processing_stop, 1, %{
            stream_id: stream_id,
            source: "api",
            success: true,
            processing_time: result.metadata.processing_time
          })

          send_json(conn, 200, response)

        {:error, reason} ->
          Metrics.record(:audio_processing_error, 1, %{
            stream_id: stream_id,
            source: "api",
            error: reason
          })

          send_json(conn, 500, %{
            stream_id: stream_id,
            error: "Processing failed: #{reason}"
          })
      end
    end
  end

  # ========== WEBHOOK DISCORD ==========

  post "/webhooks/discord" do
    signature = get_req_header(conn, "x-signature-ed25519") |> List.first()
    timestamp = get_req_header(conn, "x-signature-timestamp") |> List.first()

    if is_nil(signature) or is_nil(timestamp) do
      send_json(conn, 401, %{error: "Missing signature headers"})
    else
      {:ok, body, _} = read_body(conn)

      if not verify_discord_signature(body, signature, timestamp) do
        send_json(conn, 401, %{error: "Invalid signature"})
      else
        case Jason.decode(body) do
          {:ok, event_data} ->
            case handle_discord_event(event_data) do
              {:ok, result} ->
                Metrics.record(:webhook_discord_processed, 1, %{
                  event_type: event_data["type"],
                  event_id: event_data["id"]
                })
                send_json(conn, 200, %{status: "ok", result: result})

              {:error, reason} ->
                Metrics.record(:webhook_discord_error, 1, %{
                  event_type: event_data["type"],
                  event_id: event_data["id"],
                  error: reason
                })
                send_json(conn, 400, %{error: reason})
            end

          {:error, json_error} ->
            send_json(conn, 400, %{error: "Invalid JSON: #{inspect(json_error)}"})
        end
      end
    end
  end

  # Подтверждение webhook (GET)
  get "/webhooks/discord" do
    send_json(conn, 200, %{status: "webhook ready"})
  end

  # ========== РЕПОРТЫ ==========

  post "/api/reports" do
    %{"user_id" => user_id, "reason" => reason, "details" => details} = conn.body_params
    guild_id = conn.body_params["guild_id"]

    case Report.send(user_id, guild_id, reason, details) do
      :ok ->
        Metrics.record(:report_created, 1, %{user_id: user_id, reason: reason})
        send_json(conn, 201, %{status: "reported"})

      {:error, reason} ->
        send_json(conn, 400, %{error: reason})
    end
  end

  # ========== CATCH-ALL ==========

  match _ do
    send_json(conn, 404, %{error: "Not found"})
  end

  # ========== ERROR HANDLING ==========

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{kind: kind, reason: reason, stack: stack}) do
    Logger.error("Router error: #{inspect(reason)}")

    Metrics.record(:router_error, 1, %{
      kind: kind,
      path: conn.request_path,
      method: conn.method
    })

    send_json(conn, 500, %{error: "Internal server error"})
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp send_json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  defp verify_discord_signature(body, signature, timestamp) do
    public_key = Application.get_env(:music_core, :discord_public_key)

    if is_nil(public_key) do
      Logger.warning("Discord public key not configured")
      false
    else
      message = timestamp <> body

      case Ed25519.verify(message, Base.decode64!(signature), public_key) do
        {:ok, true} -> true
        _ -> false
      end
    end
  rescue
    _ -> false
  end

  defp handle_discord_event(%{"type" => 1}) do
    # Ping
    {:ok, %{type: 1}}
  end

  defp handle_discord_event(%{"type" => 2} = event) do
    # Interaction
    data = event["data"] || %{}
    command_name = data["name"]

    case Commands.handle(command_name, %{
      user_id: get_user_id(event),
      guild_id: event["guild_id"],
      channel_id: event["channel_id"],
      data: data
    }) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_discord_event({:discord_event, event}) do
    case event do
      %{"type" => type} when type in [3, 4, 5] ->
        case Commands.handle_interaction(event) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end
      _ ->
        {:ok, :ignored}
    end
  end

  defp handle_discord_event(event) do
    Logger.info("Unhandled Discord event type: #{event["type"]}")
    {:ok, %{}}
  end

  defp get_user_id(event) do
    case event do
      %{"member" => %{"user" => %{"id" => id}}} -> id
      %{"user" => %{"id" => id}} -> id
      %{"author" => %{"id" => id}} -> id
      _ -> nil
    end
  end

  defp get_health_status do
    %{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: Application.spec(:music_core, :vsn) |> to_string(),
      services: %{
        database: check_database_health(),
        cache: check_cache_health()
      }
    }
  end

  defp check_database_health do
    try do
      Report.get_stats(days_ago(1))
      "healthy"
    rescue
      _ -> "unhealthy"
    end
  end

  defp check_cache_health do
    try do
      _ = Cache.size(:audio_cache)
      "healthy"
    rescue
      _ -> "unhealthy"
    end
  end

  defp days_ago(n) do
    DateTime.utc_now()
    |> DateTime.add(-n * 86_400, :second)
  end
end
