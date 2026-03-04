defmodule Agency.Delivery do
  @moduledoc """
  Manages the execution layer: Features (sprint-scoped) and Tasks (hourly estimates).

  Also provides workload and cost analysis queries used for capacity planning
  and tracking scope drift against the project baseline.

  ## Rate resolution

  Task costs use a three-tier rate lookup (most specific wins):

    1. `task.rate_snapshot`     — rate captured at assignment time (immutable history)
    2. `project_member.billing_rate` — project-specific override (e.g. negotiated rate)
    3. `user.hourly_rate`       — person's current default rate

  The snapshot is written automatically by `create_task/1` and `update_task/2`
  whenever `assignee_id` is set or changed.
  """

  import Ecto.Query
  alias Agency.Repo
  alias Agency.Accounts.User
  alias Agency.Delivery.{Feature, Task}
  alias Agency.Planning.ProjectMember
  alias Agency.Sprints.Sprint

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

  @doc "Returns features with sprint, team members, and tasks preloaded. Avoids N+1 on project page."
  def list_features_with_details(project_id) do
    list_features(project_id)
    |> Repo.preload([:sprint, :resources, team: [team_members: [:user]], tasks: [:assignee, :resources]])
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

  @doc """
  Creates a task and automatically snapshots the effective rate if an assignee is set.
  """
  def create_task(attrs \\ %{}) do
    changeset = Task.changeset(%Task{}, attrs)

    changeset =
      with assignee_id when not is_nil(assignee_id) <- Ecto.Changeset.get_change(changeset, :assignee_id),
           feature_id when not is_nil(feature_id) <- Ecto.Changeset.get_change(changeset, :feature_id),
           project_id when not is_nil(project_id) <- feature_project_id(feature_id),
           rate when not is_nil(rate) <- effective_rate(assignee_id, project_id) do
        Ecto.Changeset.put_change(changeset, :rate_snapshot, rate)
      else
        _ -> changeset
      end

    Repo.insert(changeset)
  end

  @doc """
  Updates a task. Re-snapshots the rate if `assignee_id` changes.
  """
  def update_task(%Task{} = task, attrs) do
    changeset = Task.changeset(task, attrs)

    changeset =
      with assignee_id when not is_nil(assignee_id) <- Ecto.Changeset.get_change(changeset, :assignee_id),
           project_id when not is_nil(project_id) <- feature_project_id(task.feature_id),
           rate when not is_nil(rate) <- effective_rate(assignee_id, project_id) do
        Ecto.Changeset.put_change(changeset, :rate_snapshot, rate)
      else
        _ -> changeset
      end

    Repo.update(changeset)
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
  - total_estimated_hours: sum of estimated_hours across those tasks
  """
  def workload_by_sprint(sprint_id) do
    Repo.all(
      from t in Task,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == t.assignee_id,
        where: f.sprint_id == ^sprint_id,
        group_by: [u.id, u.name, u.discipline, u.seniority],
        order_by: [desc: sum(t.estimated_hours)],
        select: %{
          user_id: u.id,
          user_name: u.name,
          discipline: u.discipline,
          seniority: u.seniority,
          task_count: count(t.id),
          total_estimated_hours: sum(t.estimated_hours)
        }
    )
  end

  @doc """
  Returns task load per user across all features for a project.
  Useful for identifying overloaded team members during project planning.
  """
  def workload_by_project(project_id) do
    Repo.all(
      from t in Task,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == t.assignee_id,
        where: f.project_id == ^project_id,
        group_by: [u.id, u.name, u.discipline, u.seniority],
        order_by: [desc: sum(t.estimated_hours)],
        select: %{
          user_id: u.id,
          user_name: u.name,
          discipline: u.discipline,
          seniority: u.seniority,
          task_count: count(t.id),
          total_estimated_hours: sum(t.estimated_hours)
        }
    )
  end

  # ---------------------------------------------------------------------------
  # Cost estimation
  # ---------------------------------------------------------------------------

  @doc """
  Estimates the total cost of a project.

  Rate resolution per task: rate_snapshot → project billing_rate → user hourly_rate.

  Pass `only_baseline: true` to get the baseline (planned) cost only,
  which you can compare to the full cost to measure scope drift.
  """
  def estimate_project_cost(project_id, opts \\ []) do
    only_baseline = Keyword.get(opts, :only_baseline, false)

    query =
      from t in Task,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == t.assignee_id,
        left_join: pm in ProjectMember,
          on: pm.project_id == f.project_id and pm.user_id == t.assignee_id,
        where: f.project_id == ^project_id and not is_nil(t.estimated_hours),
        select:
          sum(
            fragment(
              "? * COALESCE(?, ?, ?)",
              t.estimated_hours,
              t.rate_snapshot,
              pm.billing_rate,
              u.hourly_rate
            )
          )

    query = if only_baseline, do: where(query, [_t, f], f.is_baseline == true), else: query

    Repo.one(query) || Decimal.new(0)
  end

  @doc "Estimates the cost of a single feature based on its assigned tasks."
  def estimate_feature_cost(feature_id) do
    Repo.one(
      from t in Task,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == t.assignee_id,
        left_join: pm in ProjectMember,
          on: pm.project_id == f.project_id and pm.user_id == t.assignee_id,
        where: t.feature_id == ^feature_id and not is_nil(t.estimated_hours),
        select:
          sum(
            fragment(
              "? * COALESCE(?, ?, ?)",
              t.estimated_hours,
              t.rate_snapshot,
              pm.billing_rate,
              u.hourly_rate
            )
          )
    ) || Decimal.new(0)
  end

  @doc """
  Returns estimated hours grouped by team member, month, and project.

  The month anchor is the sprint's `start_date`; falls back to the task's
  `due_date` if no sprint is assigned. Tasks with neither date are excluded.

  Pass `project_id: id` to scope to a single project. Without it, all
  projects are included so the caller can aggregate freely.

  Each row is a map with keys:
    user_id, user_name, discipline, month (%Date{}), project_id, total_hours, task_count
  """
  def workload_by_month(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)

    query =
      from t in Task,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == t.assignee_id,
        left_join: s in Sprint, on: s.id == f.sprint_id,
        where:
          not is_nil(t.estimated_hours) and
            not is_nil(fragment("COALESCE(?, ?)", s.start_date, t.due_date)),
        group_by: [
          u.id,
          u.name,
          u.discipline,
          fragment("DATE_TRUNC('month', COALESCE(?, ?))::date", s.start_date, t.due_date),
          f.project_id
        ],
        order_by: [
          asc: fragment("DATE_TRUNC('month', COALESCE(?, ?))::date", s.start_date, t.due_date),
          asc: u.name
        ],
        select: %{
          user_id: u.id,
          user_name: u.name,
          discipline: u.discipline,
          month: fragment("DATE_TRUNC('month', COALESCE(?, ?))::date", s.start_date, t.due_date),
          project_id: f.project_id,
          total_hours: sum(t.estimated_hours),
          task_count: count(t.id)
        }

    query =
      if project_id,
        do: where(query, [_t, f], f.project_id == ^project_id),
        else: query

    Repo.all(query)
  end

  # ---------------------------------------------------------------------------
  # Resources
  # ---------------------------------------------------------------------------

  def list_resources_for_feature(feature_id) do
    alias Agency.Delivery.Resource
    Repo.all(from r in Resource, where: r.feature_id == ^feature_id, order_by: [asc: r.inserted_at])
  end

  def list_resources_for_task(task_id) do
    alias Agency.Delivery.Resource
    Repo.all(from r in Resource, where: r.task_id == ^task_id, order_by: [asc: r.inserted_at])
  end

  def create_resource(attrs) do
    alias Agency.Delivery.Resource
    %Resource{}
    |> Resource.changeset(attrs)
    |> Repo.insert()
  end

  def delete_resource(resource_id) do
    alias Agency.Delivery.Resource
    case Repo.get(Resource, resource_id) do
      nil -> {:error, :not_found}
      resource -> Repo.delete(resource)
    end
  end

  # ---------------------------------------------------------------------------
  # Weekly notes
  # ---------------------------------------------------------------------------

  @doc """
  Returns all tasks whose `updated_at` falls within the given week.

  `week_start` is a `%Date{}` representing the Monday of the week.
  Results are preloaded with assignee, resources, and the parent
  feature (with its own resources and project) — ready for markdown rendering.
  """
  def tasks_for_week(%Date{} = week_start) do
    start_dt = DateTime.new!(week_start, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(Date.add(week_start, 7), ~T[00:00:00], "Etc/UTC")

    Repo.all(
      from t in Task,
        where: t.updated_at >= ^start_dt and t.updated_at < ^end_dt,
        order_by: [asc: t.inserted_at],
        preload: [:assignee, :resources, feature: [:resources, :project]]
    )
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp feature_project_id(feature_id) do
    Repo.one(from f in Feature, where: f.id == ^feature_id, select: f.project_id)
  end

  defp effective_rate(user_id, project_id) do
    pm = Repo.get_by(ProjectMember, user_id: user_id, project_id: project_id)

    cond do
      pm && pm.billing_rate -> pm.billing_rate
      true -> Repo.one(from u in User, where: u.id == ^user_id, select: u.hourly_rate)
    end
  end
end
