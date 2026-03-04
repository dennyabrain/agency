defmodule Agency.Repo.Migrations.CreateGoals do
  use Ecto.Migration

  def change do
    create table(:goals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vision_id, references(:visions, type: :binary_id, on_delete: :nilify_all)
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :description, :text
      add :target_outcome, :text
      add :status, :string, null: false, default: "draft"
      add :target_date, :date

      timestamps(type: :utc_datetime)
    end

    create index(:goals, [:vision_id])
    create index(:goals, [:owner_id])
  end
end
