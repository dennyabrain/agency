defmodule Agency.Repo.Migrations.CreateProjectMembers do
  use Ecto.Migration

  def change do
    create table(:project_members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "contributor"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_members, [:project_id, :user_id])
    create index(:project_members, [:user_id])
  end
end
