defmodule Agency.Delivery.TaskAssignee do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_hours [1, 2, 3, 4, 6, 8, 12, 16, 24]

  schema "task_assignees" do
    field :estimated_hours, :integer
    field :rate_snapshot, :decimal

    belongs_to :task, Agency.Delivery.Task
    belongs_to :assignee, Agency.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(task_assignee, attrs) do
    task_assignee
    |> cast(attrs, [:task_id, :user_id, :estimated_hours, :rate_snapshot])
    |> validate_required([:task_id, :user_id, :estimated_hours])
    |> validate_inclusion(:estimated_hours, @valid_hours,
      message: "must be one of #{Enum.join(@valid_hours, ", ")} hours"
    )
    |> unique_constraint([:task_id, :user_id], message: "person is already assigned to this task")
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:user_id)
  end
end
