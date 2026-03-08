defmodule Agency.Repo.Migrations.CreateTimeBlocks do
  use Ecto.Migration

  def change do
    create table(:time_blocks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :start_at, :naive_datetime, null: false
      add :end_at, :naive_datetime, null: false
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:time_blocks, [:task_id])
    create index(:time_blocks, [:start_at])
  end
end
