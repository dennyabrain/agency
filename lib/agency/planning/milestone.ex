defmodule Agency.Planning.Milestone do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "milestones" do
    field :name, :string
    field :description, :string
    field :due_date, :date
    field :status, Ecto.Enum, values: [:pending, :in_progress, :completed], default: :pending

    belongs_to :project, Agency.Planning.Project

    has_many :deliverables, Agency.Planning.Deliverable

    timestamps(type: :utc_datetime)
  end

  def changeset(milestone, attrs) do
    milestone
    |> cast(attrs, [:name, :description, :due_date, :status, :project_id])
    |> validate_required([:name, :status, :project_id])
    |> foreign_key_constraint(:project_id)
  end
end
