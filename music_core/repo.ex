defmodule MusicCore.Repo do
  use Ecto.Repo,
    otp_app: :music_core,
    adapter: Ecto.Adapters.Postgres
end
