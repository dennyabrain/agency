defmodule Agency.Repo.Migrations.CreateDeliverables do
  use Ecto.Migration

  def change do
    create table(:deliverables, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :milestone_id, references(:milestones, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "pending"
      add :due_date, :date

      timestamps(type: :utc_datetime)
    end

    create index(:deliverables, [:project_id])
    create index(:deliverables, [:milestone_id])
  end
end
