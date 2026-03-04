defmodule Agency.Repo.Migrations.AddRateSnapshotToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :rate_snapshot, :decimal, precision: 10, scale: 2
    end
  end
end
