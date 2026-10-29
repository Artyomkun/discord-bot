defmodule MusicCore.Telemetry.Router do
  use Plug.Router
  import Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  # Health check
  get "/health" do
    status = %{
      status: "healthy",
      service: "elixir_phoenix",
      version: "1.0.0",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(status))
  end

  # Metrics endpoint (Prometheus format)
  get "/metrics" do
    metrics = MusicCore.Metrics.export(:prometheus)
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  # ========= АУДИО ОБРАБОТКА =========

  post "/api/audio/stream" do
    %{"url" => url, "user_id" => user_id, "guild_id" => guild_id, "action" => action} = conn.body_params

    case MusicCore.AudioStreaming.Processor.start_stream(url, user_id, guild_id) do
      {:ok, stream_id} ->
        response = %{
          success: true,
          stream_id: stream_id,
          status: "started",
          message: "Audio stream started successfully"
        }
        send_response(conn, 200, response)

      {:error, reason} ->
        response = %{
          success: false,
          error: reason,
          fallback: true
        }
        send_response(conn, 500, response)
    end
  end

  post "/api/audio/effects" do
    %{"audio_data" => audio_data, "effects" => effects, "user_id" => user_id} = conn.body_params
    preset = Map.get(conn.body_params, "preset", "balanced")

    case MusicCore.AudioEffects.EffectsManager.apply_effects(audio_data, effects, user_id, preset) do
      {:ok, processed_audio} ->
        response = %{
          success: true,
          processed: true,
          audio_data: Base.encode64(processed_audio),
          effects_applied: Map.keys(effects),
          message: "Effects applied successfully"
        }
        send_response(conn, 200, response)

      {:error, reason} ->
        response = %{
          success: false,
          error: reason,
          processed: false
        }
        send_response(conn, 500, response)
    end
  end

  post "/api/audio/from-go" do
    %{"audio_data" => audio_data, "user_id" => user_id, "guild_id" => guild_id,
      "format" => format, "effects" => effects} = conn.body_params

    case MusicCore.AudioStreaming.Processor.process_from_go(audio_data, user_id, guild_id, format, effects) do
      {:ok, result} ->
        response = Map.merge(result, %{
          success: true,
          processed: true,
          message: "Audio processed successfully"
        })
        send_response(conn, 200, response)

      {:error, reason} ->
        response = %{
          success: false,
          error: reason,
          processed: false,
          fallback: true
        }
        send_response(conn, 500, response)
    end
  end

  # ========= LAVALINK СТАТУС =========

  get "/api/lavalink/status" do
    case MusicCore.AudioStreaming.DiscordClient.status() do
      {:ok, status} ->
        lavalink_status = %{
          lavalink: "connected",
          regions: Map.get(status, :regions, []),
          active_players: Map.get(status, :active_players, 0),
          total_players: Map.get(status, :players, 0),
          uptime: Map.get(status, :uptime, 0)
        }
        send_response(conn, 200, lavalink_status)

      {:error, _reason} ->
        error_status = %{
          lavalink: "disconnected",
          regions: [],
          active_players: 0,
          total_players: 0,
          uptime: 0
        }
        send_response(conn, 503, error_status)
    end
  end

  # ========= ЭФФЕКТЫ =========

  get "/api/effects/presets" do
    user_id = Map.get(conn.query_params, "user_id")
    presets = MusicCore.AudioEffects.EffectsManager.get_presets(user_id)
    send_response(conn, 200, presets)
  end

  get "/api/users/:user_id/effects" do
    user_id = conn.path_params["user_id"]
    settings = MusicCore.AudioEffects.EffectsManager.get_user_settings(user_id)
    send_response(conn, 200, %{user_id: user_id, effects: settings})
  end

  put "/api/users/:user_id/effects" do
    user_id = conn.path_params["user_id"]
    %{"effects" => effects} = conn.body_params

    case MusicCore.AudioEffects.EffectsManager.update_user_settings(user_id, effects) do
      :ok ->
        response = %{
          success: true,
          message: "User effects updated successfully"
        }
        send_response(conn, 200, response)

      {:error, reason} ->
        response = %{
          success: false,
          error: reason
        }
        send_response(conn, 500, response)
    end
  end

  # Устаревший эндпоинт (POST вместо PUT)
  post "/api/effects/:user_id" do
    user_id = conn.path_params["user_id"]
    settings = conn.body_params

    case MusicCore.AudioEffects.EffectsManager.update_user_settings(user_id, settings) do
      :ok ->
        send_response(conn, 200, %{status: "ok"})
      {:error, reason} ->
        send_response(conn, 500, %{error: reason})
    end
  end

  # ========= ПОИСК МУЗЫКИ =========

  get "/api/music/search" do
    %{"q" => query, "source" => source} = conn.query_params
    limit = Map.get(conn.query_params, "limit", "10") |> String.to_integer()

    case MusicCore.AudioStreaming.Processor.search_music(query, source, limit) do
      {:ok, results} ->
        response = %{
          success: true,
          query: query,
          source: source,
          results: results,
          count: length(results)
        }
        send_response(conn, 200, response)

      {:error, reason} ->
        response = %{
          success: false,
          error: reason,
          query: query,
          source: source,
          results: []
        }
        send_response(conn, 500, response)
    end
  end

  # ========= УПРАВЛЕНИЕ ОЧЕРЕДЬЮ =========

  get "/api/queue/:guild_id" do
    guild_id = conn.path_params["guild_id"]
    queue = MusicCore.AudioStreaming.QueueManager.get_queue(guild_id)
    send_response(conn, 200, %{guild_id: guild_id, queue: queue})
  end

  post "/api/queue/:guild_id/tracks" do
    guild_id = conn.path_params["guild_id"]
    %{"track" => track} = conn.body_params

    case MusicCore.AudioStreaming.QueueManager.add_track(guild_id, track, %{}) do
      {:ok, position} ->
        send_response(conn, 201, %{success: true, position: position})
      {:error, reason} ->
        send_response(conn, 400, %{success: false, error: reason})
    end
  end

  delete "/api/queue/:guild_id/tracks/:track_id" do
    guild_id = conn.path_params["guild_id"]
    track_id = conn.path_params["track_id"]

    case MusicCore.AudioStreaming.QueueManager.remove_track(guild_id, track_id) do
      :ok -> send_response(conn, 200, %{success: true})
      {:error, reason} -> send_response(conn, 400, %{success: false, error: reason})
    end
  end

  # ========= ВСПОМОГАТЕЛЬНЫЕ =========

  defp send_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(data))
  end

  # ========= 404 =========

  match _ do
    response = %{
      error: "Not found",
      message: "Endpoint not implemented",
      available_endpoints: [
        "GET /health",
        "GET /metrics",
        "POST /api/audio/stream",
        "POST /api/audio/effects",
        "POST /api/audio/from-go",
        "GET /api/lavalink/status",
        "GET /api/effects/presets",
        "GET /api/users/:user_id/effects",
        "PUT /api/users/:user_id/effects",
        "GET /api/music/search",
        "GET /api/queue/:guild_id",
        "POST /api/queue/:guild_id/tracks",
        "DELETE /api/queue/:guild_id/tracks/:track_id"
      ]
    }

    send_response(conn, 404, response)
  end
end
