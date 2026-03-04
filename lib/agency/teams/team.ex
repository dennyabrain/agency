defmodule Agency.Teams.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "teams" do
    field :name, :string
    field :description, :string

    has_many :team_members, Agency.Teams.TeamMember
    has_many :members, through: [:team_members, :user]
    has_many :features, Agency.Delivery.Feature

    timestamps(type: :utc_datetime)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
  end
end
