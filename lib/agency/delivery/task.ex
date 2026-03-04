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

    field :estimated_days, :integer
    field :due_date, :date

    belongs_to :feature, Agency.Delivery.Feature
    belongs_to :assignee, Agency.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:name, :description, :status, :estimated_days, :due_date, :feature_id, :assignee_id])
    |> validate_required([:name, :status, :feature_id])
    |> validate_inclusion(:estimated_days, [1, 2, 3], message: "must be 1, 2, or 3 days")
    |> foreign_key_constraint(:feature_id)
    |> foreign_key_constraint(:assignee_id)
  end
end
