defmodule MusicCore.AudioEffects.GoBridge do
  @moduledoc "Мост к Go-процессору"

  alias MusicCore.GoProcessor.Client
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    {:ok, opts}
  end

  defdelegate process_audio(url, format, volume, effects), to: Client
  defdelegate health_check(), to: Client

  # С дополнительным логированием
  def process_audio_logged(url, format, volume, effects) do
    Logger.debug("Processing via GoBridge: format=#{format}, volume=#{volume}")
    process_audio(url, format, volume, effects)
  end

  # С проверкой доступности
  def process_audio_with_fallback(url, format, volume, effects, fallback \\ nil) do
    case health_check() do
      :ok -> process_audio(url, format, volume, effects)
      _ -> fallback
    end
  end
end
