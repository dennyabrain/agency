defmodule Agency.Repo.Migrations.CreateFeatures do
  use Ecto.Migration

  def change do
    create table(:features, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :sprint_id, references(:sprints, type: :binary_id, on_delete: :nilify_all)
      add :team_id, references(:teams, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :hypothesis, :text
      add :status, :string, null: false, default: "backlog"
      add :priority, :integer
      add :is_baseline, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:features, [:project_id])
    create index(:features, [:sprint_id])
    create index(:features, [:team_id])
  end
end
