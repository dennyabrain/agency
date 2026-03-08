defmodule Agency.Repo.Migrations.CreateTimeBlockAssignees do
  use Ecto.Migration

  def change do
    create table(:time_block_assignees, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :time_block_id,
          references(:time_blocks, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:time_block_assignees, [:time_block_id])
    create unique_index(:time_block_assignees, [:time_block_id, :user_id])
  end
end
