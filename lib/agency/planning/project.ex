defmodule Agency.Planning.Project do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "projects" do
    field :name, :string
    field :description, :string
    field :objective, :string

    field :status, Ecto.Enum,
      values: [:draft, :active, :on_hold, :completed, :archived],
      default: :draft

    field :start_date, :date
    field :end_date, :date
    field :baseline_locked_at, :utc_datetime
    field :baseline_cost, :decimal

    belongs_to :goal, Agency.Planning.Goal
    belongs_to :owner, Agency.Accounts.User

    has_many :project_members, Agency.Planning.ProjectMember
    has_many :members, through: [:project_members, :user]
    has_many :milestones, Agency.Planning.Milestone
    has_many :deliverables, Agency.Planning.Deliverable
    has_many :features, Agency.Delivery.Feature

    timestamps(type: :utc_datetime)
  end

  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :name, :description, :objective, :status,
      :start_date, :end_date, :baseline_locked_at, :baseline_cost,
      :goal_id, :owner_id
    ])
    |> validate_required([:name, :status])
    |> validate_date_order()
    |> foreign_key_constraint(:goal_id)
    |> foreign_key_constraint(:owner_id)
  end

  defp validate_date_order(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && Date.compare(end_date, start_date) == :lt do
      add_error(changeset, :end_date, "must be on or after start date")
    else
      changeset
    end
  end
end
