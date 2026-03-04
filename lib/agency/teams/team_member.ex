defmodule Agency.Teams.TeamMember do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "team_members" do
    belongs_to :team, Agency.Teams.Team
    belongs_to :user, Agency.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(team_member, attrs) do
    team_member
    |> cast(attrs, [:team_id, :user_id])
    |> validate_required([:team_id, :user_id])
    |> foreign_key_constraint(:team_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:team_id, :user_id], message: "user is already on this team")
  end
end
