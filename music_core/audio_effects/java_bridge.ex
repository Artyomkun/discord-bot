defmodule MusicCore.AudioEffects.JavaBridge do
  @moduledoc """
  Мост к Java Gateway.
  Обеспечивает отправку аудио данных на обработку в Java-сервис.
  """

  alias MusicCore.JavaGateway.Client
  require Logger
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    {:ok, opts}
  end

  @default_timeout 8000

  @doc """
  Отправляет аудио на обработку в Java Gateway.
  """
  def process_audio(stream_id, audio_data, effects, options \\ []) do
    Logger.debug("[JavaBridge] Processing stream #{stream_id}, effects: #{inspect(effects)}")

    try do
      case Client.process_audio(stream_id, audio_data, effects, options) do
        {:ok, result} ->
          Logger.debug("[JavaBridge] Successfully processed stream #{stream_id}")
          {:ok, result}

        {:error, reason} ->
          Logger.error("[JavaBridge] Failed to process stream #{stream_id}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("[JavaBridge] Exception while processing stream #{stream_id}: #{inspect(e)}")
        {:error, {:exception, e}}
    end
  end

  @doc """
  Проверяет доступность Java Gateway.
  """
  def health_check do
    case Client.health_check() do
      :ok ->
        Logger.debug("[JavaBridge] Health check passed")
        :ok

      {:error, reason} ->
        Logger.warning("[JavaBridge] Health check failed: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("[JavaBridge] Health check exception: #{inspect(e)}")
      {:error, {:exception, e}}
  end

  @doc """
  Отправляет аудио на обработку с таймаутом и fallback.
  """
  def process_audio_with_timeout(stream_id, audio_data, effects, timeout \\ @default_timeout, fallback \\ nil) do
    task = Task.async(fn ->
      process_audio(stream_id, audio_data, effects)
    end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result
      nil ->
        Logger.error("[JavaBridge] Timeout processing stream #{stream_id} after #{timeout}ms")
        fallback
    end
  end
end
