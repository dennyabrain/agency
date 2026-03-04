defmodule Agency.Planning.Deliverable do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "deliverables" do
    field :name, :string
    field :description, :string

    field :status, Ecto.Enum,
      values: [:pending, :in_review, :approved, :rejected],
      default: :pending

    field :due_date, :date

    belongs_to :project, Agency.Planning.Project
    belongs_to :milestone, Agency.Planning.Milestone

    timestamps(type: :utc_datetime)
  end

  def changeset(deliverable, attrs) do
    deliverable
    |> cast(attrs, [:name, :description, :status, :due_date, :project_id, :milestone_id])
    |> validate_required([:name, :status, :project_id])
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:milestone_id)
  end
end
