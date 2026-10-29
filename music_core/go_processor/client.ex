defmodule MusicCore.GoProcessor.Client do
  @moduledoc """
  gRPC клиент для взаимодействия с Go аудио процессором.

  Использует gRPC как основной транспорт.
  """

  require Logger

  alias MusicCore.AudioEffects.Effects.Normalizer
  alias MusicCore.Metrics

  # gRPC конфигурация
  @grpc_host "localhost"
  @grpc_port 50051

  # HTTP fallback
  @http_url "http://localhost:8082"

  # gRPC канал и заглушка
  @grpc_channel :persistent_term.get({__MODULE__, :channel}, nil)
  @grpc_stub :persistent_term.get({__MODULE__, :stub}, nil)

  @doc """
  Инициализирует gRPC соединение.
  """
  def init_grpc do
    case :grpc_client.connect(to_charlist(@grpc_host), @grpc_port) do
      {:ok, channel} ->
        stub = GoService.V1.GoService.Stub.new(channel)
        :persistent_term.put({__MODULE__, :channel}, channel)
        :persistent_term.put({__MODULE__, :stub}, stub)
        Logger.info("✅ gRPC client connected to Go service at #{@grpc_host}:#{@grpc_port}")
        {:ok, stub}

      {:error, reason} ->
        Logger.error("❌ Failed to connect gRPC: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Обрабатывает аудио через Go процессор (gRPC).
  """
  @spec process_audio(String.t(), String.t(), float(), list()) ::
          {:ok, map()} | {:error, term()}
  def process_audio(url, format \\ "opus", volume \\ 1.0, effects \\ []) do
    Metrics.record(:audio_processing_start, 1, %{source: :go, stream_id: url})

    case call_grpc(:process_audio, %{
      url: url,
      format: format,
      volume: volume,
      effects: effects,
      timestamp: System.system_time(:millisecond)
    }) do
      {:ok, response} ->
        Metrics.record(:audio_processing_stop, 1, %{source: :go, status: :success})
        {:ok, response}

      {:error, reason} ->
        # Fallback на HTTP
        Logger.warning("gRPC failed, falling back to HTTP: #{reason}")
        process_audio_http(url, format, volume, effects)
    end
  end

  defp process_audio_http(url, format, volume, effects) do
    request_body = %{
      url: url,
      format: format,
      volume: volume,
      effects: effects,
      timestamp: System.system_time(:millisecond)
    }

    case make_http_request("/api/audio/process", request_body) do
      {:ok, response} ->
        Metrics.record(:audio_processing_stop, 1, %{source: :go_http, status: :success})
        {:ok, response}
      {:error, reason} ->
        Metrics.record(:audio_processing_error, 1, %{source: :go_http, error: reason})
        {:error, reason}
    end
  end

  @doc """
  Нормализует аудио (локально, без gRPC).
  """
  @spec normalize(binary(), float(), String.t()) :: {:ok, binary()} | {:error, term()}
  def normalize(audio_data, target_peak \\ -1.0, mode \\ "peak") do
    case mode do
      "peak" -> Normalizer.normalize_peak(audio_data, target_peak)
      "rms" -> Normalizer.normalize_rms(audio_data, target_peak)
      _ -> Normalizer.normalize(audio_data, target_peak)
    end
  end

  @doc """
  Применяет эффекты к аудио данным через gRPC.
  """
  @spec apply_effects(binary(), list()) :: {:ok, binary()} | {:error, term()}
  def apply_effects(audio_data, effects) do
    case call_grpc(:apply_effects, %{
      audio_data: Base.encode64(audio_data),
      effects: effects,
      timestamp: System.system_time(:millisecond)
    }) do
      {:ok, %{processed_data: encoded_data}} ->
        case Base.decode64(encoded_data) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, :invalid_base64_response}
        end

      {:error, reason} ->
        Logger.error("gRPC apply_effects failed: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Проверяет здоровье Go процессора (gRPC).
  """
  @spec health_check() :: boolean()
  def health_check do
    case call_grpc(:health_check, %{}) do
      {:ok, %{status: "healthy"}} -> true
      _ -> false
    end
  end

  @doc """
  Получает статистику Go процессора (gRPC).
  """
  @spec get_stats() :: {:ok, map()} | {:error, term()}
  def get_stats do
    call_grpc(:get_stats, %{})
  end

  @doc """
  Конвертирует аудио формат через gRPC.
  """
  @spec convert_format(binary(), String.t(), String.t()) :: {:ok, binary()} | {:error, term()}
  def convert_format(audio_data, from_format, to_format) do
    case call_grpc(:convert_format, %{
      audio_data: Base.encode64(audio_data),
      from_format: from_format,
      to_format: to_format,
      timestamp: System.system_time(:millisecond)
    }) do
      {:ok, %{converted_data: encoded_data}} ->
        case Base.decode64(encoded_data) do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, :invalid_base64_response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ========== PRIVATE ==========

  defp call_grpc(method, request) do
    case get_stub() do
      nil ->
        {:error, :grpc_not_initialized}

      stub ->
        try do
          apply(stub, method, [request])
        rescue
          e ->
            Logger.error("gRPC call failed: #{inspect(e)}")
            {:error, e}
        end
    end
  end

  defp get_stub do
    case :persistent_term.get({__MODULE__, :stub}, nil) do
      nil ->
        case init_grpc() do
          {:ok, stub} -> stub
          _ -> nil
        end
      stub -> stub
    end
  end

  defp make_http_request(path, body, method \\ :post) do
    url = @http_url <> path
    headers = [{"Content-Type", "application/json"}]
    request_body = Jason.encode!(body)

    case :httpc.request(method, {url, headers, 'application/json', request_body}, [], []) do
      {:ok, {{_version, 200, _reason}, _headers, response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded}
          error -> error
        end

      {:ok, {{_version, status, _reason}, _headers, body}} ->
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, e}
  end
end
