defmodule MusicCore.Schema.Report do
  use Ecto.Schema
  import Ecto.Changeset

  schema "reports" do
    field :user_id, :string
    field :guild_id, :string
    field :reason, :string
    field :details, :string
    field :meta, :map
    field :status, :string, default: "new"
    field :resolved_by, :string
    field :resolution_note, :string
    field :rejected_reason, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:user_id, :guild_id, :reason, :details, :meta, :status])
    |> validate_required([:user_id, :reason])
  end

  def resolve_changeset(report, admin_id, resolution_note) do
    report
    |> cast(%{resolved_by: admin_id, resolution_note: resolution_note, status: "resolved"}, [:resolved_by, :resolution_note, :status])
    |> validate_required([:resolved_by, :status])
  end

  def reject_changeset(report, admin_id, reason) do
    report
    |> cast(%{resolved_by: admin_id, rejected_reason: reason, status: "rejected"}, [:resolved_by, :rejected_reason, :status])
    |> validate_required([:resolved_by, :rejected_reason, :status])
  end
end
