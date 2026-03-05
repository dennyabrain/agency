defmodule Agency.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :title, :string

    field :discipline, Ecto.Enum,
      values: [:design, :engineering, :research, :qa, :data, :management]

    field :seniority, Ecto.Enum,
      values: [:junior, :mid, :senior, :lead, :principal]

    field :hourly_rate, :decimal

    field :employment_type, Ecto.Enum,
      values: [:employee, :contractor],
      default: :employee

    field :app_roles, {:array, :string}, default: []

    # Auth fields
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime

    has_many :user_tokens, Agency.Accounts.UserToken
    has_many :project_memberships, Agency.Planning.ProjectMember
    has_many :projects, through: [:project_memberships, :project]
    has_many :team_memberships, Agency.Teams.TeamMember
    has_many :teams, through: [:team_memberships, :team]
    has_many :task_assignments, Agency.Delivery.TaskAssignee, foreign_key: :user_id
    has_many :assigned_tasks, through: [:task_assignments, :task]
    has_many :owned_projects, Agency.Planning.Project, foreign_key: :owner_id
    has_many :owned_goals, Agency.Planning.Goal, foreign_key: :owner_id

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for self-registration. Requires profile fields and password."
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :name, :discipline, :seniority, :password])
    |> validate_required([:email, :name, :discipline, :seniority])
    |> validate_email(opts)
    |> validate_password(opts)
  end

  @doc "Changeset for updating email address."
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_email(opts)
    |> case do
      %{changes: %{email: _}} = changeset -> changeset
      %{} = changeset -> add_error(changeset, :email, "did not change")
    end
  end

  @doc "Changeset for updating password."
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  @doc "Changeset for profile updates (name, title, discipline, seniority, hourly_rate)."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :title, :discipline, :seniority, :hourly_rate])
    |> validate_required([:name, :discipline, :seniority])
    |> validate_number(:hourly_rate, greater_than_or_equal_to: 0)
  end

  @valid_roles ~w(admin hr pm)

  @doc "Changeset for managing app-level roles. Admin use only."
  def roles_changeset(user, attrs) do
    user
    |> cast(attrs, [:app_roles])
    |> validate_subset(:app_roles, @valid_roles,
      message: "contains an invalid role. Valid roles: #{Enum.join(@valid_roles, ", ")}"
    )
  end

  @doc "Changeset for admin-initiated user creation. Includes all profile fields plus password."
  def admin_create_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :name, :title, :discipline, :seniority, :hourly_rate, :employment_type, :app_roles, :password])
    |> validate_required([:email, :name, :discipline, :seniority])
    |> validate_email(opts)
    |> validate_password(opts)
    |> validate_number(:hourly_rate, greater_than_or_equal_to: 0)
    |> validate_subset(:app_roles, @valid_roles,
      message: "contains an invalid role. Valid roles: #{Enum.join(@valid_roles, ", ")}"
    )
  end

  @doc "Changeset for admin-initiated user edits. Covers all editable fields without requiring current password."
  def admin_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :title, :discipline, :seniority, :hourly_rate, :employment_type, :app_roles])
    |> validate_required([:email, :name, :discipline, :seniority])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Agency.Repo)
    |> unique_constraint(:email)
    |> validate_number(:hourly_rate, greater_than_or_equal_to: 0)
    |> validate_subset(:app_roles, @valid_roles,
      message: "contains an invalid role. Valid roles: #{Enum.join(@valid_roles, ", ")}"
    )
  end

  @doc "Marks the user's email as confirmed."
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  @doc "Verifies the password against the stored hash."
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _), do: Bcrypt.no_user_verify()

  @doc "Validates the current password for sensitive operations (email/password changes)."
  def validate_current_password(changeset, password) do
    if valid_password?(changeset.data, password) do
      changeset
    else
      add_error(changeset, :current_password, "is not valid")
    end
  end

  defp validate_email(changeset, opts) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> maybe_validate_unique_email(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> validate_length(:password, max: 72, count: :bytes)
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  defp maybe_validate_unique_email(changeset, opts) do
    if Keyword.get(opts, :validate_email, true) do
      changeset
      |> unsafe_validate_unique(:email, Agency.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end
end
