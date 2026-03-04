defmodule Agency.Delivery.Feature do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "features" do
    field :name, :string
    field :description, :string
    field :hypothesis, :string

    field :status, Ecto.Enum,
      values: [:backlog, :in_progress, :completed, :cancelled],
      default: :backlog

    field :priority, :integer
    field :is_baseline, :boolean, default: false

    belongs_to :project, Agency.Planning.Project
    belongs_to :sprint, Agency.Sprints.Sprint
    belongs_to :team, Agency.Teams.Team

    has_many :tasks, Agency.Delivery.Task
    has_many :resources, Agency.Delivery.Resource

    timestamps(type: :utc_datetime)
  end

  def changeset(feature, attrs) do
    feature
    |> cast(attrs, [
      :name, :description, :hypothesis, :status,
      :priority, :is_baseline, :project_id, :sprint_id, :team_id
    ])
    |> validate_required([:name, :status, :project_id])
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:sprint_id)
    |> foreign_key_constraint(:team_id)
  end
end
