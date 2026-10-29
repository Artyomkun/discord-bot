defmodule MusicCore.WebSocket.Codec do
  @moduledoc """
  Кодек для преобразования Protobuf <-> WebSocket сообщений.
  """

  defdelegate auth_response_encode(resp), to: Client.V1.AuthResponse, as: :encode
  defdelegate auth_response_new(data), to: Client.V1.AuthResponse, as: :new
  defdelegate audio_response_encode(resp), to: Audio.V1.AudioProcessResponse, as: :encode
  defdelegate audio_response_new(data), to: Audio.V1.AudioProcessResponse, as: :new

  defdelegate auth_request_decode(data), to: Client.V1.AuthRequest, as: :decode
  defdelegate subscribe_request_decode(data), to: Client.V1.SubscribeRequest, as: :decode
  defdelegate audio_request_decode(data), to: Audio.V1.AudioProcessRequest, as: :decode

  @type message ::
    {:auth, Client.V1.AuthRequest.t()}
    | {:subscribe, Client.V1.SubscribeRequest.t()}
    | {:audio_process, Audio.V1.AudioProcessRequest.t()}

  @spec decode(binary()) :: {:ok, message()} | {:error, term()}
  def decode(data) do
    with {:ok, req} <- auth_request_decode(data) do
      {:ok, {:auth, req}}
    else
      {:error, _} ->
        with {:ok, req} <- subscribe_request_decode(data) do
          {:ok, {:subscribe, req}}
        else
          {:error, _} ->
            case audio_request_decode(data) do
              {:ok, req} -> {:ok, {:audio_process, req}}
              error -> error
            end
        end
    end
  end

  @spec encode_auth_response(map() | term()) :: binary()
  def encode_auth_response(data) when is_map(data) do
    auth_module = Module.concat(["Client.V1.AuthResponse"])

    cond do
      is_struct(data, auth_module) ->
        auth_response_encode(data)
      true ->
        data
        |> auth_response_new()
        |> auth_response_encode()
    end
  end

  @spec encode_audio_response(map() | term()) :: binary()
  def encode_audio_response(data) when is_map(data) do
    audio_module = Module.concat(["Audio.V1.AudioProcessResponse"])

    cond do
      is_struct(data, audio_module) ->
        audio_response_encode(data)
      true ->
        data
        |> audio_response_new()
        |> audio_response_encode()
    end
  end

  @spec encode(term()) :: binary()
  def encode(resp) do
    auth_module = Module.concat(["Client.V1.AuthResponse"])
    audio_module = Module.concat(["Audio.V1.AudioProcessResponse"])

    cond do
      is_struct(resp, auth_module) ->
        auth_response_encode(resp)
      is_struct(resp, audio_module) ->
        audio_response_encode(resp)
      true ->
        raise ArgumentError, "Unknown response type: #{inspect(resp)}"
    end
  end
end
