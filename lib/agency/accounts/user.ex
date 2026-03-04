defmodule Agency.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :title, :string

    field :discipline, Ecto.Enum,
      values: [:design, :engineering, :research, :qa, :data, :management]

    field :seniority, Ecto.Enum,
      values: [:junior, :mid, :senior, :lead, :principal]

    field :daily_rate, :decimal

    has_many :project_memberships, Agency.Planning.ProjectMember
    has_many :projects, through: [:project_memberships, :project]
    has_many :team_memberships, Agency.Teams.TeamMember
    has_many :teams, through: [:team_memberships, :team]
    has_many :assigned_tasks, Agency.Delivery.Task, foreign_key: :assignee_id
    has_many :owned_projects, Agency.Planning.Project, foreign_key: :owner_id
    has_many :owned_goals, Agency.Planning.Goal, foreign_key: :owner_id

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :title, :discipline, :seniority, :daily_rate])
    |> validate_required([:email, :name, :discipline, :seniority])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> validate_number(:daily_rate, greater_than_or_equal_to: 0)
    |> unique_constraint(:email)
  end
end
