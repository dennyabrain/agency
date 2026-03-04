defmodule Agency.Repo.Migrations.CreateVisions do
  use Ecto.Migration

  def change do
    create table(:visions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :statement, :text, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
