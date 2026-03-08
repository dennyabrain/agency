defmodule Agency.Delivery do
  @moduledoc """
  Manages the execution layer: Features (sprint-scoped) and Tasks (hourly estimates).

  Also provides workload and cost analysis queries used for capacity planning
  and tracking scope drift against the project baseline.

  ## Rate resolution

  Task costs use a three-tier rate lookup (most specific wins):

    1. `task_assignee.rate_snapshot` — rate captured at assignment time (immutable history)
    2. `project_member.billing_rate` — project-specific override (e.g. negotiated rate)
    3. `user.hourly_rate`            — person's current default rate

  The snapshot is written automatically by `add_task_assignee/2` when a person
  is added to a task.
  """

  import Ecto.Query
  alias Agency.Repo
  alias Agency.Accounts.User
  alias Agency.Delivery.{Feature, Task, TaskAssignee, TimeBlock, TimeBlockAssignee}
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

  @doc "Returns features with sprint, owner, and tasks preloaded. Avoids N+1 on project page."
  def list_features_with_details(project_id) do
    list_features(project_id)
    |> Repo.preload([
      :sprint,
      :resources,
      :owner,
      tasks: [task_assignees: [:assignee], resources: []]
    ])
  end

  @doc "Loads all features with sprint and tasks preloaded for the Gantt chart view."
  def list_all_features_for_gantt do
    Repo.all(from f in Feature, preload: [:sprint, :tasks])
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
    |> Repo.preload([
      :sprint,
      :project,
      :resources,
      :owner,
      tasks: [task_assignees: [:assignee], resources: []]
    ])
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
        preload: [task_assignees: [:assignee], resources: []]
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
  # Task assignees
  # ---------------------------------------------------------------------------

  @doc "Returns all assignees for a task, with user preloaded."
  def list_task_assignees(task_id) do
    Repo.all(
      from ta in TaskAssignee,
        where: ta.task_id == ^task_id,
        order_by: [asc: ta.inserted_at],
        preload: [:assignee]
    )
  end

  @doc """
  Adds a person to a task with their own estimated hours. Snapshots their
  effective rate (project billing rate → user hourly rate) at this moment.
  """
  def add_task_assignee(%Task{} = task, attrs) do
    user_id = attrs[:user_id] || attrs["user_id"]
    project_id = if task.feature_id, do: feature_project_id(task.feature_id)

    rate = if user_id && project_id, do: effective_rate(user_id, project_id)

    %TaskAssignee{}
    |> TaskAssignee.changeset(Map.put(attrs, "task_id", task.id))
    |> Ecto.Changeset.put_change(:rate_snapshot, rate)
    |> Repo.insert()
  end

  @doc "Removes a person from a task."
  def remove_task_assignee(task_assignee_id) do
    case Repo.get(TaskAssignee, task_assignee_id) do
      nil -> {:error, :not_found}
      ta -> Repo.delete(ta)
    end
  end

  @doc "Updates estimated hours for a task assignee. Rate snapshot is unchanged."
  def update_task_assignee(%TaskAssignee{} = ta, attrs) do
    ta
    |> TaskAssignee.changeset(attrs)
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Time blocks
  # ---------------------------------------------------------------------------

  @doc "Returns all time blocks for a task, ordered by start time, with assignees preloaded."
  def list_time_blocks(task_id) do
    Repo.all(
      from tb in TimeBlock,
        where: tb.task_id == ^task_id,
        order_by: [asc: tb.start_at],
        preload: [time_block_assignees: [:assignee]]
    )
  end

  def get_time_block!(id), do: Repo.get!(TimeBlock, id)

  @doc """
  Returns time blocks for calendar display, with the full task → feature → project
  chain preloaded. Accepts opts:
    - `:project_id` — filter to one project
    - `:from_dt`    — only blocks whose end_at >= from_dt
    - `:to_dt`      — only blocks whose start_at <= to_dt
  """
  def list_time_blocks_for_calendar(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    from_dt = Keyword.get(opts, :from_dt)
    to_dt = Keyword.get(opts, :to_dt)

    query =
      from tb in TimeBlock,
        join: t in Task, on: t.id == tb.task_id,
        join: f in Feature, on: f.id == t.feature_id,
        order_by: [asc: tb.start_at],
        preload: [time_block_assignees: [:assignee], task: [feature: :project]]

    query =
      if project_id, do: where(query, [_tb, _t, f], f.project_id == ^project_id), else: query

    query = if from_dt, do: where(query, [tb], tb.end_at >= ^from_dt), else: query
    query = if to_dt, do: where(query, [tb], tb.start_at <= ^to_dt), else: query

    Repo.all(query)
  end

  @doc """
  Creates a time block for a task with the given assignees.

  `assignee_ids` should be a list of user IDs (strings). Only IDs present in the
  task's own assignees are accepted — invalid IDs are silently skipped.
  """
  def create_time_block(%Task{} = task, attrs, assignee_ids \\ []) do
    attrs = Map.put(attrs, "task_id", task.id)
    changeset = TimeBlock.changeset(%TimeBlock{}, attrs)

    if changeset.valid? do
      Repo.transaction(fn ->
        time_block = Repo.insert!(changeset)

        for user_id <- assignee_ids, user_id != "" do
          %TimeBlockAssignee{}
          |> TimeBlockAssignee.changeset(%{time_block_id: time_block.id, user_id: user_id})
          |> Repo.insert!(on_conflict: :nothing)
        end

        Repo.preload(time_block, time_block_assignees: [:assignee])
      end)
    else
      {:error, changeset}
    end
  end

  @doc "Deletes a time block and its assignees (cascade)."
  def delete_time_block(id) do
    case Repo.get(TimeBlock, id) do
      nil -> {:error, :not_found}
      tb -> Repo.delete(tb)
    end
  end

  def change_time_block(%TimeBlock{} = tb, attrs \\ %{}), do: TimeBlock.changeset(tb, attrs)

  # ---------------------------------------------------------------------------
  # Workload analysis
  # ---------------------------------------------------------------------------

  @doc """
  Returns task load per user for a given sprint.

  Each entry includes:
  - user_id, user_name
  - task_count: number of task-assignee rows (appearances on tasks)
  - total_estimated_hours: sum of estimated_hours across those task-assignee rows
  """
  def workload_by_sprint(sprint_id) do
    Repo.all(
      from ta in TaskAssignee,
        join: t in Task, on: t.id == ta.task_id,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == ta.user_id,
        where: f.sprint_id == ^sprint_id,
        group_by: [u.id, u.name, u.discipline, u.seniority],
        order_by: [desc: sum(ta.estimated_hours)],
        select: %{
          user_id: u.id,
          user_name: u.name,
          discipline: u.discipline,
          seniority: u.seniority,
          task_count: count(ta.id),
          total_estimated_hours: sum(ta.estimated_hours)
        }
    )
  end

  @doc """
  Returns task load per user across all features for a project.
  Useful for identifying overloaded team members during project planning.
  """
  def workload_by_project(project_id) do
    Repo.all(
      from ta in TaskAssignee,
        join: t in Task, on: t.id == ta.task_id,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == ta.user_id,
        where: f.project_id == ^project_id,
        group_by: [u.id, u.name, u.discipline, u.seniority],
        order_by: [desc: sum(ta.estimated_hours)],
        select: %{
          user_id: u.id,
          user_name: u.name,
          discipline: u.discipline,
          seniority: u.seniority,
          task_count: count(ta.id),
          total_estimated_hours: sum(ta.estimated_hours)
        }
    )
  end

  # ---------------------------------------------------------------------------
  # Cost estimation
  # ---------------------------------------------------------------------------

  @doc """
  Estimates the total cost of a project.

  Cost = Σ(task_assignee.estimated_hours × effective_rate) across all assignees
  on all tasks belonging to the project.

  Rate resolution per assignee: rate_snapshot → project billing_rate → user hourly_rate.

  Pass `only_baseline: true` to sum only assignees on features marked as baseline,
  which you can compare to the full cost to measure scope drift.
  """
  def estimate_project_cost(project_id, opts \\ []) do
    only_baseline = Keyword.get(opts, :only_baseline, false)

    query =
      from ta in TaskAssignee,
        join: t in Task, on: t.id == ta.task_id,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == ta.user_id,
        left_join: pm in ProjectMember,
          on: pm.project_id == f.project_id and pm.user_id == ta.user_id,
        where: f.project_id == ^project_id,
        select:
          sum(
            fragment(
              "? * COALESCE(?, ?, ?)",
              ta.estimated_hours,
              ta.rate_snapshot,
              pm.billing_rate,
              u.hourly_rate
            )
          )

    query = if only_baseline, do: where(query, [_ta, _t, f], f.is_baseline == true), else: query

    Repo.one(query) || Decimal.new(0)
  end

  @doc "Estimates the cost of a single feature based on its task assignees."
  def estimate_feature_cost(feature_id) do
    Repo.one(
      from ta in TaskAssignee,
        join: t in Task, on: t.id == ta.task_id,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == ta.user_id,
        left_join: pm in ProjectMember,
          on: pm.project_id == f.project_id and pm.user_id == ta.user_id,
        where: t.feature_id == ^feature_id,
        select:
          sum(
            fragment(
              "? * COALESCE(?, ?, ?)",
              ta.estimated_hours,
              ta.rate_snapshot,
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
      from ta in TaskAssignee,
        join: t in Task, on: t.id == ta.task_id,
        join: f in Feature, on: f.id == t.feature_id,
        join: u in User, on: u.id == ta.user_id,
        left_join: s in Sprint, on: s.id == f.sprint_id,
        where:
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
          total_hours: sum(ta.estimated_hours),
          task_count: count(ta.id)
        }

    query =
      if project_id,
        do: where(query, [_ta, _t, f], f.project_id == ^project_id),
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
  Results are preloaded with task_assignees, resources, and the parent
  feature (with its own resources and project) — ready for markdown rendering.
  """
  def tasks_for_week(%Date{} = week_start) do
    start_dt = DateTime.new!(week_start, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(Date.add(week_start, 7), ~T[00:00:00], "Etc/UTC")

    Repo.all(
      from t in Task,
        where: t.updated_at >= ^start_dt and t.updated_at < ^end_dt,
        order_by: [asc: t.inserted_at],
        preload: [task_assignees: [:assignee], resources: [], feature: [:resources, :project]]
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
