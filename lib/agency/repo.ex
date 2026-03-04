defmodule Agency.Repo do
  use Ecto.Repo,
    otp_app: :agency,
    adapter: Ecto.Adapters.Postgres
end
