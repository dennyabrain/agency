defmodule Agency.Delivery.TimeBlock do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "time_blocks" do
    field :title, :string
    field :start_at, :naive_datetime
    field :end_at, :naive_datetime

    belongs_to :task, Agency.Delivery.Task
    has_many :time_block_assignees, Agency.Delivery.TimeBlockAssignee
    has_many :assignees, through: [:time_block_assignees, :assignee]

    timestamps(type: :utc_datetime)
  end

  def changeset(time_block, attrs) do
    time_block
    |> cast(attrs, [:title, :start_at, :end_at, :task_id])
    |> validate_required([:start_at, :end_at, :task_id])
    |> validate_end_after_start()
    |> foreign_key_constraint(:task_id)
  end

  defp validate_end_after_start(changeset) do
    start_at = get_field(changeset, :start_at)
    end_at = get_field(changeset, :end_at)

    if start_at && end_at && NaiveDateTime.compare(end_at, start_at) != :gt do
      add_error(changeset, :end_at, "must be after start time")
    else
      changeset
    end
  end
end
