defmodule Agency.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @hash_algorithm :sha256
  @rand_size 32

  # Tokens for password reset / email confirmation expire after 1 day.
  @reset_password_validity_in_days 1
  @confirm_validity_in_days 7
  # Email change tokens expire after 7 days.
  @change_email_validity_in_days 7
  # Session tokens expire after 60 days.
  @session_validity_in_days 60

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, Agency.Accounts.User

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc "Generates a token that will be stored in a signed-cookie or the live view session."
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %Agency.Accounts.UserToken{token: token, context: "session", user_id: user.id}}
  end

  @doc "Checks if the token is valid and returns the matching query."
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end

  @doc "Builds a token with a hashed counter part. Used for email-based flows."
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %Agency.Accounts.UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc "Checks if the token is valid and returns the matching query."
  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)
        days = days_for_context(context)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^days, "day") and token.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Checks if a change email token is valid and returns the matching query."
  def verify_change_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Returns the token struct for the given token value and context."
  def by_token_and_context_query(token, context) do
    from Agency.Accounts.UserToken, where: [token: ^token, context: ^context]
  end

  @doc "Returns all tokens for a user for the given contexts."
  def by_user_and_contexts_query(user, :all) do
    from t in Agency.Accounts.UserToken, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, [_ | _] = contexts) do
    from t in Agency.Accounts.UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end

  defp days_for_context("confirm"), do: @confirm_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days
end
