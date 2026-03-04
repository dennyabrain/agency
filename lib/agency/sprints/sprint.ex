defmodule Agency.Sprints.Sprint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sprints" do
    field :number, :integer
    field :name, :string
    field :start_date, :date
    field :end_date, :date

    has_many :features, Agency.Delivery.Feature

    timestamps(type: :utc_datetime)
  end

  def changeset(sprint, attrs) do
    sprint
    |> cast(attrs, [:number, :name, :start_date, :end_date])
    |> validate_required([:number, :start_date, :end_date])
    |> validate_number(:number, greater_than: 0)
    |> validate_date_order()
    |> unique_constraint(:number)
  end

  defp validate_date_order(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)

    if start_date && end_date && Date.compare(end_date, start_date) == :lt do
      add_error(changeset, :end_date, "must be on or after start date")
    else
      changeset
    end
  end
end
