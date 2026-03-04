defmodule Agency.Repo.Migrations.CreateMilestones do
  use Ecto.Migration

  def change do
    create table(:milestones, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :due_date, :date
      add :status, :string, null: false, default: "pending"

      timestamps(type: :utc_datetime)
    end

    create index(:milestones, [:project_id])
  end
end
