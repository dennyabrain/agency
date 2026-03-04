defmodule Agency.Delivery do
  @moduledoc """
  Manages the execution layer: Features (sprint-scoped) and Tasks (1-3 days).

  Also provides workload and cost analysis queries used for capacity planning
  and tracking scope drift against the project baseline.
  """

  import Ecto.Query
  alias Agency.Repo
  alias Agency.Accounts.User
  alias Agency.Delivery.{Feature, Task}

  # ---------------------------------------------------------------------------
  # Features
  # ---------------------------------------------------------------------------

  def list_features(project_id) do
    Repo.all(
      from f in Feature,
        where: f.project_id == ^project_id,
        order_by: [asc: f.priority, asc: f.inserted_at]
    )
  end

  def list_features_for_sprint(sprint_id) do
    Repo.all(
      from f in Feature,
        where: f.sprint_id == ^sprint_id,
        order_by: [asc: f.priority]
    )
  end

  @doc "Returns only features that were part of the original baseline plan."
  def list_baseline_features(project_id) do
    Repo.all(
      from f in Feature,
        where: f.project_id == ^project_id and f.is_baseline == true,
        order_by: [asc: f.priority]
    )
  end

  @doc "Returns features added after the baseline was locked (scope additions)."
  def list_scope_additions(project_id) do
    Repo.all(
      from f in Feature,
        where: f.project_id == ^project_id and f.is_baseline == false,
        order_by: [asc: f.inserted_at]
    )
  end

  def get_feature!(id), do: Repo.get!(Feature, id)

  def get_feature_with_details!(id) do
    Repo.get!(Feature, id)
    |> Repo.preload([:sprint, :project, team: [team_members: [:user]], tasks: [:assignee]])
  end

  def create_feature(attrs \\ %{}) do
    %Feature{}
    |> Feature.changeset(attrs)
    |> Repo.insert()
  end

  def update_feature(%Feature{} = feature, attrs) do
    feature
    |> Feature.changeset(attrs)
    |> Repo.update()
  end

  def delete_feature(%Feature{} = feature), do: Repo.delete(feature)

  def change_feature(%Feature{} = feature, attrs \\ %{}), do: Feature.changeset(feature, attrs)

  # ---------------------------------------------------------------------------
  # Tasks
  # ---------------------------------------------------------------------------

  def list_tasks(feature_id) do
    Repo.all(
      from t in Task,
        where: t.feature_id == ^feature_id,
        order_by: [asc: t.inserted_at],
        preload: [:assignee]
    )
  end

  def get_task!(id), do: Repo.get!(Task, id)

  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def delete_task(%Task{} = task), do: Repo.delete(task)

  def change_task(%Task{} = task, attrs \\ %{}), do: Task.changeset(task, attrs)

  # ---------------------------------------------------------------------------
  # Workload analysis
  # ---------------------------------------------------------------------------

  @doc """
  Returns task load per user for a given sprint.

  Each entry includes:
  - user_id, user_name
  - task_count: number of tasks assigned
  - total_estimated_days: sum of estimated_days across those tasks
  """
  def workload_by_sprint(sprint_id) do
    Repo.all(
      from t in Task,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == t.assignee_id,
        where: f.sprint_id == ^sprint_id,
        group_by: [u.id, u.name, u.discipline, u.seniority],
        order_by: [desc: sum(t.estimated_days)],
        select: %{
          user_id: u.id,
          user_name: u.name,
          discipline: u.discipline,
          seniority: u.seniority,
          task_count: count(t.id),
          total_estimated_days: sum(t.estimated_days)
        }
    )
  end

  @doc """
  Returns task load per user across all active sprints for a project.
  Useful for identifying overloaded team members during project planning.
  """
  def workload_by_project(project_id) do
    Repo.all(
      from t in Task,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == t.assignee_id,
        where: f.project_id == ^project_id,
        group_by: [u.id, u.name, u.discipline, u.seniority],
        order_by: [desc: sum(t.estimated_days)],
        select: %{
          user_id: u.id,
          user_name: u.name,
          discipline: u.discipline,
          seniority: u.seniority,
          task_count: count(t.id),
          total_estimated_days: sum(t.estimated_days)
        }
    )
  end

  # ---------------------------------------------------------------------------
  # Cost estimation
  # ---------------------------------------------------------------------------

  @doc """
  Estimates the total cost of a project.

  Pass `only_baseline: true` to get the baseline (planned) cost only,
  which you can compare to the full cost to measure scope drift.
  """
  def estimate_project_cost(project_id, opts \\ []) do
    only_baseline = Keyword.get(opts, :only_baseline, false)

    query =
      from t in Task,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == t.assignee_id,
        where:
          f.project_id == ^project_id and
            not is_nil(t.estimated_days) and
            not is_nil(u.daily_rate),
        select: sum(fragment("? * ?", t.estimated_days, u.daily_rate))

    query =
      if only_baseline do
        where(query, [_t, f], f.is_baseline == true)
      else
        query
      end

    Repo.one(query) || Decimal.new(0)
  end

  @doc "Estimates the cost of a single feature based on its assigned tasks."
  def estimate_feature_cost(feature_id) do
    Repo.one(
      from t in Task,
        join: u in User, on: u.id == t.assignee_id,
        where:
          t.feature_id == ^feature_id and
            not is_nil(t.estimated_days) and
            not is_nil(u.daily_rate),
        select: sum(fragment("? * ?", t.estimated_days, u.daily_rate))
    ) || Decimal.new(0)
  end
end
