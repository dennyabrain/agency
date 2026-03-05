defmodule Agency.Delivery.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasks" do
    field :name, :string
    field :description, :string

    field :status, Ecto.Enum,
      values: [:todo, :in_progress, :in_review, :done, :blocked],
      default: :todo

    field :due_date, :date

    belongs_to :feature, Agency.Delivery.Feature

    has_many :task_assignees, Agency.Delivery.TaskAssignee
    has_many :assignees, through: [:task_assignees, :assignee]
    has_many :resources, Agency.Delivery.Resource

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:name, :description, :status, :due_date, :feature_id])
    |> validate_required([:name, :status, :feature_id])
    |> foreign_key_constraint(:feature_id)
  end
end
