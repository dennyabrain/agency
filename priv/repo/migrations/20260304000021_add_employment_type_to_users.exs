defmodule Agency.Repo.Migrations.AddEmploymentTypeToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :employment_type, :string, null: false, default: "employee"
    end
  end
end
