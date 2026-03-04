defmodule Agency.Sprints do
  @moduledoc """
  Manages the global sprint calendar shared across all teams and projects.
  """

  import Ecto.Query
  alias Agency.Repo
  alias Agency.Sprints.Sprint

  def list_sprints do
    Repo.all(from s in Sprint, order_by: [desc: s.number])
  end

  @doc "Loads sprints with features, teams, and team members for the Gantt chart."
  def list_sprints_with_details do
    Repo.all(
      from s in Sprint,
        order_by: [asc: s.start_date, asc: s.number],
        preload: [features: [:tasks, team: [team_members: :user]]]
    )
  end

  def get_sprint!(id), do: Repo.get!(Sprint, id)

  @doc "Returns the sprint whose date range contains today, or nil."
  def current_sprint do
    today = Date.utc_today()

    Repo.one(
      from s in Sprint,
        where: s.start_date <= ^today and s.end_date >= ^today,
        limit: 1
    )
  end

  @doc "Returns the next sprint number to use (max + 1)."
  def next_sprint_number do
    Repo.one(from s in Sprint, select: coalesce(max(s.number), 0)) + 1
  end

  def create_sprint(attrs \\ %{}) do
    %Sprint{}
    |> Sprint.changeset(attrs)
    |> Repo.insert()
  end

  def update_sprint(%Sprint{} = sprint, attrs) do
    sprint
    |> Sprint.changeset(attrs)
    |> Repo.update()
  end

  def delete_sprint(%Sprint{} = sprint), do: Repo.delete(sprint)

  def change_sprint(%Sprint{} = sprint, attrs \\ %{}), do: Sprint.changeset(sprint, attrs)
end
