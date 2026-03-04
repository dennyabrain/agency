defmodule Agency.Repo.Migrations.CreateResources do
  use Ecto.Migration

  def change do
    create table(:resources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :url, :text, null: false
      add :kind, :string, null: false, default: "website"
      add :feature_id, references(:features, type: :binary_id, on_delete: :delete_all)
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:resources, [:feature_id])
    create index(:resources, [:task_id])
  end
end
