defmodule Agency.Planning.Goal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "goals" do
    field :name, :string
    field :description, :string
    field :target_outcome, :string
    field :status, Ecto.Enum, values: [:draft, :active, :achieved, :abandoned], default: :draft
    field :target_date, :date

    belongs_to :vision, Agency.Planning.Vision
    belongs_to :owner, Agency.Accounts.User

    has_many :projects, Agency.Planning.Project

    timestamps(type: :utc_datetime)
  end

  def changeset(goal, attrs) do
    goal
    |> cast(attrs, [:name, :description, :target_outcome, :status, :target_date, :vision_id, :owner_id])
    |> validate_required([:name, :status])
    |> foreign_key_constraint(:vision_id)
    |> foreign_key_constraint(:owner_id)
  end
end
