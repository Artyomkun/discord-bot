defmodule MusicCore.AudioStream do
  @moduledoc """
  Модуль для управления аудио потоками.

  Предоставляет высокоуровневый API для работы с аудио стримам.
  """

  require Logger

  alias MusicCore.{Metrics, AudioStream.Manager}

  @doc """
  Создает новый аудио поток.
  """
  @spec create_stream(String.t(), String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def create_stream(guild_id, user_id, options \\ %{}) do
    stream_id = generate_stream_id()

    case Manager.register_stream(stream_id, guild_id, Map.put(options, :user_id, user_id)) do
      :ok ->  
        Metrics.record(:stream_created, 1, %{guild_id: guild_id, user_id: user_id})
        Logger.info("Created audio stream #{stream_id} for guild #{guild_id}")
        {:ok, stream_id}

      {:error, reason} ->
        Metrics.error(:stream_creation_failed, reason, %{guild_id: guild_id, user_id: user_id})
        {:error, reason}
    end
  end

  @doc """
  Уничтожает аудио поток.
  """
  @spec destroy_stream(String.t()) :: :ok | {:error, term()}
  def destroy_stream(stream_id) do
    case Manager.unregister_stream(stream_id) do
      :ok ->
        Metrics.record(:stream_destroyed, 1, %{stream_id: stream_id})
        Logger.info("Destroyed audio stream #{stream_id}")
        :ok

      {:error, reason} ->
        Metrics.error(:stream_destruction_failed, reason, %{stream_id: stream_id})
        {:error, reason}
    end
  end

  @doc """
  Получает активные стримы для гильдии.
  """
  @spec active_streams(String.t()) :: list()
  def active_streams(guild_id) do
    Manager.get_guild_streams(guild_id)
  end

  @doc """
  Получает общее количество активных стримов.
  """
  @spec active_streams_count() :: non_neg_integer()
  def active_streams_count do
    Manager.active_streams_count()
  end

  @doc """
  Проверяет существование стрима.
  """
  @spec stream_exists?(String.t()) :: boolean()
  def stream_exists?(stream_id) do
    case Manager.get_stream_info(stream_id) do
      {:ok, _} -> true
      {:error, :not_found} -> false
    end
  end

  @doc """
  Обновляет метаданные стрима.
  """
  @spec update_metadata(String.t(), map()) :: :ok | {:error, term()}
  def update_metadata(stream_id, metadata) do
    case Manager.get_stream(stream_id) do
      nil ->
        {:error, :stream_not_found}

      stream ->
        case validate_metadata(metadata) do
          :ok ->
            updated = %{stream | metadata: Map.merge(stream.metadata, metadata)}
            Manager.update_stream(updated)

          error ->
            error
        end
    end
  end

  @doc """
  Валидирует метаданные потока перед обновлением или созданием.
  """
  defp validate_metadata(metadata) do
    required_fields = [:name, :user_id]
    missing = Enum.filter(required_fields, &(not Map.has_key?(metadata, &1)))

    if missing == [] do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp generate_stream_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "stream_#{timestamp}_#{random}"
  end
end
