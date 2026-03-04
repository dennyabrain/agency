defmodule Agency.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :goal_id, references(:goals, type: :binary_id, on_delete: :nilify_all)
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :objective, :text
      add :status, :string, null: false, default: "draft"
      add :start_date, :date
      add :end_date, :date
      add :baseline_locked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:projects, [:goal_id])
    create index(:projects, [:owner_id])
  end
end
