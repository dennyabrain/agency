defmodule Agency.Repo.Migrations.AddBaselineCostToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :baseline_cost, :decimal, precision: 15, scale: 2
    end
  end
end
