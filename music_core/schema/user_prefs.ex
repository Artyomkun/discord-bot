defmodule MusicCore.Schema.UserPrefs do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_prefs" do
    field :user_id, :string
    field :prefs, :map

    timestamps()
  end

  def changeset(prefs, attrs) do
    prefs
    |> cast(attrs, [:user_id, :prefs])
    |> validate_required([:user_id])
  end
end
