defmodule Agency.Repo.Migrations.RenameEstimatedDaysToEstimatedHours do
  use Ecto.Migration

  def change do
    rename table(:tasks), :estimated_days, to: :estimated_hours
  end
end
