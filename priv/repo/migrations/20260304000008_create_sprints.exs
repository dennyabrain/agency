defmodule Agency.Repo.Migrations.CreateSprints do
  use Ecto.Migration

  def change do
    create table(:sprints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :number, :integer, null: false
      add :name, :string
      add :start_date, :date, null: false
      add :end_date, :date, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:sprints, [:number])
  end
end
