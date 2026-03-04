defmodule Agency.Teams do
  @moduledoc """
  Manages ad-hoc cross-functional teams assembled per feature.
  """

  import Ecto.Query
  alias Agency.Repo
  alias Agency.Teams.{Team, TeamMember}

  # ---------------------------------------------------------------------------
  # Teams
  # ---------------------------------------------------------------------------

  def list_teams do
    Repo.all(from t in Team, order_by: [asc: t.name])
  end

  def get_team!(id), do: Repo.get!(Team, id)

  def get_team_with_members!(id) do
    Repo.get!(Team, id) |> Repo.preload(team_members: [:user])
  end

  def create_team(attrs \\ %{}) do
    %Team{}
    |> Team.changeset(attrs)
    |> Repo.insert()
  end

  def update_team(%Team{} = team, attrs) do
    team
    |> Team.changeset(attrs)
    |> Repo.update()
  end

  def delete_team(%Team{} = team), do: Repo.delete(team)

  def change_team(%Team{} = team, attrs \\ %{}), do: Team.changeset(team, attrs)

  # ---------------------------------------------------------------------------
  # Team Members
  # ---------------------------------------------------------------------------

  def list_team_members(team_id) do
    Repo.all(
      from tm in TeamMember,
        where: tm.team_id == ^team_id,
        join: u in assoc(tm, :user),
        order_by: [asc: u.name],
        preload: [user: u]
    )
  end

  def add_team_member(attrs \\ %{}) do
    %TeamMember{}
    |> TeamMember.changeset(attrs)
    |> Repo.insert()
  end

  def remove_team_member(%TeamMember{} = tm), do: Repo.delete(tm)

  def get_team_member!(id), do: Repo.get!(TeamMember, id)

  def change_team_member(%TeamMember{} = tm, attrs \\ %{}) do
    TeamMember.changeset(tm, attrs)
  end
end
