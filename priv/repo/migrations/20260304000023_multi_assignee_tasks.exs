defmodule Agency.Repo.Migrations.MultiAssigneeTasks do
  use Ecto.Migration

  def up do
    create table(:task_assignees, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :estimated_hours, :integer, null: false
      add :rate_snapshot, :decimal, precision: 10, scale: 2

      timestamps(type: :utc_datetime)
    end

    create index(:task_assignees, [:task_id])
    create unique_index(:task_assignees, [:task_id, :user_id])

    # Migrate existing single-assignee data
    execute """
    INSERT INTO task_assignees (id, task_id, user_id, estimated_hours, rate_snapshot, inserted_at, updated_at)
    SELECT gen_random_uuid(), id, assignee_id, estimated_hours, rate_snapshot, NOW(), NOW()
    FROM tasks
    WHERE assignee_id IS NOT NULL AND estimated_hours IS NOT NULL
    """

    alter table(:tasks) do
      remove :assignee_id
      remove :estimated_hours
      remove :rate_snapshot
    end
  end

  def down do
    alter table(:tasks) do
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :estimated_hours, :integer
      add :rate_snapshot, :decimal, precision: 10, scale: 2
    end

    # Best-effort: restore one assignee per task (pick the one with most hours)
    execute """
    UPDATE tasks t
    SET assignee_id = ta.user_id,
        estimated_hours = ta.estimated_hours,
        rate_snapshot = ta.rate_snapshot
    FROM (
      SELECT DISTINCT ON (task_id) task_id, user_id, estimated_hours, rate_snapshot
      FROM task_assignees
      ORDER BY task_id, estimated_hours DESC
    ) ta
    WHERE t.id = ta.task_id
    """

    drop table(:task_assignees)
  end
end
