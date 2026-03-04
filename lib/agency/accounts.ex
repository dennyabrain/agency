defmodule Agency.Accounts do
  @moduledoc """
  Manages users — their profiles, disciplines, and seniority.
  """

  import Ecto.Query
  alias Agency.Repo
  alias Agency.Accounts.User

  def list_users do
    Repo.all(from u in User, order_by: [asc: u.name])
  end

  def list_users_by_discipline(discipline) do
    Repo.all(from u in User, where: u.discipline == ^discipline, order_by: [asc: u.name])
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email), do: Repo.get_by(User, email: email)

  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def delete_user(%User{} = user), do: Repo.delete(user)

  def change_user(%User{} = user, attrs \\ %{}), do: User.changeset(user, attrs)
end
