defmodule Agency.Planning.Vision do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "visions" do
    field :statement, :string

    has_many :goals, Agency.Planning.Goal

    timestamps(type: :utc_datetime)
  end

  def changeset(vision, attrs) do
    vision
    |> cast(attrs, [:statement])
    |> validate_required([:statement])
  end
end
