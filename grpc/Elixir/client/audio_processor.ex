defmodule ElixirClient.Client.AudioProcessor do
  @moduledoc """
  gRPC клиент для AudioProcessor сервиса.
  """

  use GRPC.Client, service: Grpc.Proto.Audio.AudioProcessor.Service
  alias Grpc.Proto.Audio.{AudioProcessRequest, AudioProcessResponse}
  alias Grpc.Proto.Audio.AudioProcessor.Stub, as: AudioStub

  @doc """
  Вызывает ProcessAudio метод.
  """
  @spec process_audio(AudioProcessRequest.t()) ::
    {:ok, AudioProcessResponse.t()} | {:error, GRPC.RPCError.t()}
  def process_audio(request) do
    channel = GRPC.Stub.connect("localhost:50051")
    AudioStub.process_audio(channel, request)
  end
end
