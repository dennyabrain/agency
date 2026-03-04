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

    field :estimated_hours, :integer
    field :due_date, :date

    belongs_to :feature, Agency.Delivery.Feature
    belongs_to :assignee, Agency.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @valid_hours [1, 2, 3, 4, 6, 8, 12, 16, 24]

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:name, :description, :status, :estimated_hours, :due_date, :feature_id, :assignee_id])
    |> validate_required([:name, :status, :feature_id])
    |> validate_inclusion(:estimated_hours, @valid_hours,
      message: "must be one of #{Enum.join(@valid_hours, ", ")} hours"
    )
    |> foreign_key_constraint(:feature_id)
    |> foreign_key_constraint(:assignee_id)
  end
end
