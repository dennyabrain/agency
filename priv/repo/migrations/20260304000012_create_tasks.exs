defmodule Agency.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :feature_id, references(:features, type: :binary_id, on_delete: :delete_all), null: false
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "todo"
      add :estimated_days, :integer
      add :due_date, :date

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:feature_id])
    create index(:tasks, [:assignee_id])
  end
end
