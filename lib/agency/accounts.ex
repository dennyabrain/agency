defmodule Agency.Accounts do
  @moduledoc """
  Manages users — their profiles, disciplines, and authentication.
  """

  import Ecto.Query
  alias Agency.Repo
  alias Agency.Accounts.{User, UserToken, UserNotifier}

  # ---------------------------------------------------------------------------
  # User queries
  # ---------------------------------------------------------------------------

  def list_users do
    Repo.all(from u in User, order_by: [asc: u.name])
  end

  def list_users_by_discipline(discipline) do
    Repo.all(from u in User, where: u.discipline == ^discipline, order_by: [asc: u.name])
  end

  # ---------------------------------------------------------------------------
  # Role management (admin only — enforce in the caller)
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Admin user management
  # ---------------------------------------------------------------------------

  def admin_create_user(attrs) do
    %User{}
    |> User.admin_create_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_new(attrs \\ %{}) do
    User.admin_create_changeset(%User{}, attrs, hash_password: false, validate_email: false)
  end

  def admin_update_user(%User{} = user, attrs) do
    user
    |> User.admin_changeset(attrs)
    |> Repo.update()
  end

  def change_user_admin(%User{} = user, attrs \\ %{}) do
    User.admin_changeset(user, attrs)
  end

  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc "Replaces a user's app_roles. Pass an empty list to remove all roles."
  def update_user_roles(%User{} = user, roles) when is_list(roles) do
    user
    |> User.roles_changeset(%{app_roles: roles})
    |> Repo.update()
  end

  def change_user_roles(%User{} = user, attrs \\ %{}) do
    User.roles_changeset(user, attrs)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  # ---------------------------------------------------------------------------
  # Profile updates
  # ---------------------------------------------------------------------------

  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  def change_user_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  # ---------------------------------------------------------------------------
  # Email changes
  # ---------------------------------------------------------------------------

  def change_user_email(%User{} = user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  def apply_user_email(%User{} = user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(change_user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp change_user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  def deliver_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  # ---------------------------------------------------------------------------
  # Password changes
  # ---------------------------------------------------------------------------

  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  def update_user_password(%User{} = user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  # ---------------------------------------------------------------------------
  # Session tokens
  # ---------------------------------------------------------------------------

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  # ---------------------------------------------------------------------------
  # Confirmation
  # ---------------------------------------------------------------------------

  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  # ---------------------------------------------------------------------------
  # Password reset
  # ---------------------------------------------------------------------------

  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end
end
