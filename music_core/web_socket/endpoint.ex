defmodule MusicCore.WebSocket.Endpoint do
  @moduledoc """
  WebSocket endpoint для MusicCore.

  Обеспечивает:
  - WebSocket соединения для клиентов (Go, Java)
  - Health check для gRPC gateway
  - Метрики и мониторинг
  """

  use Plug.Router
  require Logger

  alias MusicCore.WebSocket.{WebSockAdapter, Handler, Health}
  alias MusicCore.{Metrics, Cache}

  # Plug pipeline
  plug Plug.Logger
  plug :match
  plug :dispatch

  # WebSocket endpoint
  match "/ws" do
    conn
    |> WebSockAdapter.upgrade(
      Handler,
      [],
      timeout: 60_000
    )
    |> halt()
  end

  # Health check
  match "/health" do
    case Health.check() do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{status: "healthy"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{status: "unhealthy", reason: reason}))
    end
  end

  # Readiness probe
  match "/ready" do
    if Health.ready?() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ready"}))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(503, Jason.encode!(%{status: "not ready"}))
    end
  end

  # Metrics endpoint
  match "/metrics" do
    metrics = Metrics.export(:prometheus)

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, metrics)
  end

  # Cache stats endpoint
  match "/cache/stats" do
    stats = %{
      audio_cache: Cache.stats(:audio_cache),
      effects_cache: Cache.stats(:effects_cache)
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(stats))
  end

  # gRPC-Web endpoint
  match "/grpc/*path" do
    case conn.method do
      "POST" ->
        handle_grpc_request(conn, path)

      "OPTIONS" ->
        conn
        |> put_resp_header("access-control-allow-origin", "*")
        |> put_resp_header("access-control-allow-methods", "POST, OPTIONS")
        |> put_resp_header("access-control-allow-headers", "content-type, x-grpc-web, x-user-agent")
        |> put_resp_header("access-control-max-age", "86400")
        |> send_resp(204, "")

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(405, Jason.encode!(%{error: "Method not allowed"}))
    end
  end

  # Catch-all
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{
      error: "Not found",
      available: ["/ws", "/health", "/ready", "/metrics", "/cache/stats"]
    }))
  end

  # ========== PRIVATE FUNCTIONS ==========

  defp handle_grpc_request(conn, _path) do
    {:ok, body, _} = Plug.Conn.read_body(conn)
    content_type = get_req_header(conn, "content-type") |> List.first()

    case content_type do
      "application/grpc-web-text" ->
        case decode_grpc_web_request(body) do
          {:ok, decoded_data, trailers} ->
            process_grpc_message(conn, decoded_data, trailers)

          {:error, reason} ->
            conn
            |> put_resp_content_type("application/grpc-web-text")
            |> put_resp_header("grpc-status", "3")
            |> put_resp_header("grpc-message", reason)
            |> send_resp(200, "")
        end

      "application/grpc" ->
        process_grpc_message(conn, body, %{})

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(415, Jason.encode!(%{error: "Unsupported content type"}))
    end
  end

  defp process_grpc_message(conn, data, trailers) do
    try do
      response_data = handle_grpc_call(data)

      encoded_response = encode_grpc_web_response(response_data, trailers)

      conn
      |> put_resp_content_type("application/grpc-web-text")
      |> put_resp_header("grpc-status", "0")
      |> put_resp_header("grpc-message", "")
      |> put_resp_header("content-length", Integer.to_string(byte_size(encoded_response)))
      |> send_resp(200, encoded_response)
    rescue
      e ->
        Logger.error("gRPC call failed: #{inspect(e)}")

        conn
        |> put_resp_content_type("application/grpc-web-text")
        |> put_resp_header("grpc-status", "13")
        |> put_resp_header("grpc-message", "Internal server error")
        |> send_resp(200, "")
    end
  end

  defp handle_grpc_call(data) do
    # Заглушка для gRPC вызовов
    # В реальном коде здесь будет вызов соответствующих сервисов
    Logger.debug("gRPC call received, size: #{byte_size(data)} bytes")

    # Отправляем пустой ответ для тестирования
    encoded_response = ""

    encoded_response
  end

  defp encode_grpc_web_response(data, trailers) when is_binary(data) do
    data_len = byte_size(data)
    data_header = <<0::1, data_len::4-big>>

    trailers_bin = encode_trailers(trailers)
    trailers_len = byte_size(trailers_bin)

    trailers_header = if trailers_len > 0 do
      <<128::1, trailers_len::4-big>>
    else
      <<>>
    end

    data_header <> data <> trailers_header <> trailers_bin
  end

  defp encode_trailers(trailers) when map_size(trailers) == 0 do
    ""
  end

  defp encode_trailers(trailers) do
    Enum.map_join(trailers, "\r\n", fn {key, value} -> "#{key}: #{value}" end) <> "\r\n"
  end

  defp decode_grpc_web_request(data) when is_binary(data) do
    decode_grpc_web_request(data, %{})
  end

  defp decode_grpc_web_request(<<>>, acc) do
    {:ok, "", acc}
  end

  defp decode_grpc_web_request(<<0::1, len::4-big, rest::binary>>, acc) when len <= byte_size(rest) do
    <<message::binary-size(len), remaining::binary>> = rest
    decode_grpc_web_request(remaining, Map.put(acc, :message, message))
  end

  defp decode_grpc_web_request(<<128::1, len::4-big, rest::binary>>, acc) when len <= byte_size(rest) do
    <<trailers_bin::binary-size(len), remaining::binary>> = rest
    trailers = decode_trailers(trailers_bin)
    decode_grpc_web_request(remaining, Map.merge(acc, trailers))
  end

  defp decode_grpc_web_request(_, _) do
    {:error, "Invalid gRPC-Web format"}
  end

  defp decode_trailers(<<>>) do
    %{}
  end

  defp decode_trailers(binary) when is_binary(binary) do
    binary
    |> String.split("\r\n", trim: true)
    |> Enum.map(&String.split(&1, ": ", parts: 2))
    |> Enum.filter(fn parts -> length(parts) == 2 end)
    |> Map.new(fn [key, value] -> {key, value} end)
  end
end
