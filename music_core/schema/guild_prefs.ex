defmodule MusicCore.Schema.GuildPrefs do
  use Ecto.Schema
  import Ecto.Changeset

  schema "guild_prefs" do
    field :guild_id, :string
    field :prefs, :map

    timestamps()
  end

  def changeset(prefs, attrs) do
    prefs
    |> cast(attrs, [:guild_id, :prefs])
    |> validate_required([:guild_id])
  end
end
