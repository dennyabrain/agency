defmodule Agency.Delivery.TimeBlockAssignee do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "time_block_assignees" do
    belongs_to :time_block, Agency.Delivery.TimeBlock
    belongs_to :assignee, Agency.Accounts.User, foreign_key: :user_id

    timestamps(type: :utc_datetime)
  end

  def changeset(time_block_assignee, attrs) do
    time_block_assignee
    |> cast(attrs, [:time_block_id, :user_id])
    |> validate_required([:time_block_id, :user_id])
    |> unique_constraint([:time_block_id, :user_id],
      message: "person is already assigned to this time block"
    )
    |> foreign_key_constraint(:time_block_id)
    |> foreign_key_constraint(:user_id)
  end
end
