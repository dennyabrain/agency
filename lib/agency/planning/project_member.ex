defmodule Agency.Planning.ProjectMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_members" do
    field :role, Ecto.Enum, values: [:owner, :contributor, :stakeholder], default: :contributor
    field :billing_rate, :decimal

    belongs_to :project, Agency.Planning.Project
    belongs_to :user, Agency.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(project_member, attrs) do
    project_member
    |> cast(attrs, [:role, :billing_rate, :project_id, :user_id])
    |> validate_required([:role, :project_id, :user_id])
    |> validate_number(:billing_rate, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:project_id, :user_id], message: "user is already a member of this project")
  end
end
