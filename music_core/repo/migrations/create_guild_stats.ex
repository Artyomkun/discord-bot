defmodule MusicCore.Repo.Migrations.CreateGuildStats do
  use Ecto.Migration

  def change do
    create table(:guild_stats) do
      add :guild_id, :string, null: false
      add :processed_tracks, :integer, default: 0, null: false
      add :total_duration_seconds, :integer, default: 0, null: false
      add :last_processed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:guild_stats, [:guild_id], name: :guild_stats_guild_id_index)
    create index(:guild_stats, [:processed_tracks])
    create index(:guild_stats, [:total_duration_seconds])
  end
end
