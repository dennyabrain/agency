defmodule Agency.Repo.Migrations.AddBillingRateToProjectMembers do
  use Ecto.Migration

  def change do
    alter table(:project_members) do
      add :billing_rate, :decimal, precision: 10, scale: 2
    end
  end
end
