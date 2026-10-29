defmodule MusicCore.Schema.GuildStats do
  @moduledoc """
  Схема для хранения статистики по гильдиям (серверам) в базе данных.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [order_by: 2, limit: 2, where: 2]
  import MusicCore.Repo

  @type t :: %__MODULE__{
    id: integer(),
    guild_id: String.t(),
    processed_tracks: integer(),
    total_duration_seconds: integer(),
    last_processed_at: DateTime.t() | nil,
    inserted_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  schema "guild_stats" do
    field :guild_id, :string
    field :processed_tracks, :integer, default: 0
    field :total_duration_seconds, :integer, default: 0
    field :last_processed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Создание изменений для новой статистики.
  """
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(guild_stats, attrs) do
    guild_stats
    |> cast(attrs, [:guild_id, :processed_tracks, :total_duration_seconds, :last_processed_at])
    |> validate_required([:guild_id])
    |> unique_constraint(:guild_id, name: :guild_stats_guild_id_index)
  end

  @doc """
  Обновление статистики для гильдии.
  """
  @spec increment_tracks(String.t(), integer()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def increment_tracks(guild_id, increment \\ 1) do
    case Repo.get_by(__MODULE__, guild_id: guild_id) do
      nil ->
        %__MODULE__{}
        |> changeset(%{
          guild_id: guild_id,
          processed_tracks: increment,
          last_processed_at: DateTime.utc_now()
        })
        |> Repo.insert()

      stats ->
        stats
        |> change(%{
          processed_tracks: stats.processed_tracks + increment,
          last_processed_at: DateTime.utc_now()
        })
        |> Repo.update()
    end
  end

  @doc """
  Обновление общей длительности обработанного аудио.
  """
  @spec add_duration(String.t(), integer()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def add_duration(guild_id, duration_seconds) do
    case Repo.get_by(__MODULE__, guild_id: guild_id) do
      nil ->
        %__MODULE__{}
        |> changeset(%{
          guild_id: guild_id,
          total_duration_seconds: duration_seconds,
          last_processed_at: DateTime.utc_now()
        })
        |> Repo.insert()

      stats ->
        stats
        |> change(%{
          total_duration_seconds: stats.total_duration_seconds + duration_seconds,
          last_processed_at: DateTime.utc_now()
        })
        |> Repo.update()
    end
  end

  @doc """
  Получить статистику гильдии.
  """
  @spec get_by_guild(String.t()) :: {:ok, t()} | {:error, :not_found}
  def get_by_guild(guild_id) do
    case Repo.get_by(__MODULE__, guild_id: guild_id) do
      nil -> {:error, :not_found}
      stats -> {:ok, stats}
    end
  end

  @doc """
  Получить топ гильдий по обработке.
  """
  @spec top_by_tracks(integer()) :: list(t())
  def top_by_tracks(limit \\ 10) do
    __MODULE__
    |> order_by(desc: :processed_tracks)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Получить топ гильдий по общему времени.
  """
  @spec top_by_duration(integer()) :: list(t())
  def top_by_duration(limit \\ 10) do
    __MODULE__
    |> order_by(desc: :total_duration_seconds)
    |> limit(^limit)
    |> Repo.all()
  end
end
