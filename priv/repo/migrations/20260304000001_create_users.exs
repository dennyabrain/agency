defmodule Agency.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string, null: false
      add :title, :string
      add :discipline, :string, null: false
      add :seniority, :string, null: false
      add :daily_rate, :decimal, precision: 10, scale: 2

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
  end
end
