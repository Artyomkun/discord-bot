defmodule MusicCore.Statistics do
  @moduledoc """
  Сбор статистики по обработке аудио.
  """

  require Logger
  import Ecto.Query, only: [from: 2]
  import Ecto.Query.API, only: [sum: 1, max: 1]
  alias MusicCore.{Buffer, Schema.GuildStats}
  alias MusicCore.Schema.GuildStats

  @doc """
  Записывает информацию об обработанном аудио для гильдии.
  """
  def record_processed(guild_id, output_file) do
    # Получаем размер файла
    case File.stat(output_file) do
      {:ok, %{size: size}} ->
        # Записываем в БД
        %GuildStats{}
        |> GuildStats.changeset(%{
          guild_id: guild_id,
          files_processed: 1,
          total_bytes: size,
          processed_at: DateTime.utc_now()
        })
        |> Buffer.insert()

        # Отправляем метрику
        :telemetry.execute([:music_core, :statistics, :processed], %{
          size: size
        }, %{
          guild_id: guild_id
        })

        Logger.debug("Recorded processed file for guild #{guild_id}: #{size} bytes")
        :ok

      {:error, reason} ->
        Logger.error("Failed to get file size for guild #{guild_id}: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Получает статистику по гильдии.
  """
  def get_stats(guild_id) do
    query = from g in GuildStats,
      where: g.guild_id == ^guild_id,
      select: %{
        total_files: sum(g.files_processed),
        total_bytes: sum(g.total_bytes),
        last_processed: max(g.processed_at)
      }

    case MusicCore.Repo.one(query) do
      nil -> {:ok, %{total_files: 0, total_bytes: 0}}
      stats -> {:ok, stats}
    end
  end
end
