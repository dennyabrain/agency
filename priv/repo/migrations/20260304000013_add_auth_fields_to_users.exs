defmodule Agency.Repo.Migrations.AddAuthFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
    end
  end
end
