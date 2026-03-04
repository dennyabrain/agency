defmodule Agency.Delivery.Resource do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "resources" do
    field :title, :string
    field :url, :string

    field :kind, Ecto.Enum,
      values: [:github, :gdoc, :gsheet, :figma, :notion, :website, :other],
      default: :website

    belongs_to :feature, Agency.Delivery.Feature
    belongs_to :task, Agency.Delivery.Task

    timestamps(type: :utc_datetime)
  end

  def changeset(resource, attrs) do
    resource
    |> cast(attrs, [:title, :url, :kind, :feature_id, :task_id])
    |> validate_required([:url, :kind])
    |> validate_format(:url, ~r/^https?:\/\/.+/i, message: "must start with http:// or https://")
    |> validate_length(:url, max: 2048)
    |> validate_length(:title, max: 255)
    |> validate_owner()
    |> foreign_key_constraint(:feature_id)
    |> foreign_key_constraint(:task_id)
  end

  # Ensures exactly one parent FK is set
  defp validate_owner(changeset) do
    feature_id = get_field(changeset, :feature_id)
    task_id = get_field(changeset, :task_id)

    cond do
      is_nil(feature_id) and is_nil(task_id) ->
        add_error(changeset, :base, "resource must belong to a feature or a task")

      not is_nil(feature_id) and not is_nil(task_id) ->
        add_error(changeset, :base, "resource cannot belong to both a feature and a task")

      true ->
        changeset
    end
  end
end
