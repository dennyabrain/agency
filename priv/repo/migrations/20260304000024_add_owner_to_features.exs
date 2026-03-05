defmodule Agency.Repo.Migrations.AddOwnerToFeatures do
  use Ecto.Migration

  def change do
    alter table(:features) do
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:features, [:owner_id])
  end
end
