defmodule Agency.Repo.Migrations.AddAppRolesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :app_roles, {:array, :string}, default: [], null: false
    end
  end
end
