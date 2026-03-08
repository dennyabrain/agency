defmodule Agency.Planning do
  @moduledoc """
  Manages the LVT planning hierarchy: Visions, Goals, Projects, Milestones,
  Deliverables, and project membership.
  """

  import Ecto.Query
  alias Agency.Repo
  alias Agency.Planning.{Vision, Goal, Project, ProjectMember, Milestone, Deliverable}

  # ---------------------------------------------------------------------------
  # Visions
  # ---------------------------------------------------------------------------

  def list_visions, do: Repo.all(Vision)

  def get_vision!(id), do: Repo.get!(Vision, id)

  def create_vision(attrs \\ %{}) do
    %Vision{}
    |> Vision.changeset(attrs)
    |> Repo.insert()
  end

  def update_vision(%Vision{} = vision, attrs) do
    vision
    |> Vision.changeset(attrs)
    |> Repo.update()
  end

  def delete_vision(%Vision{} = vision), do: Repo.delete(vision)

  def change_vision(%Vision{} = vision, attrs \\ %{}), do: Vision.changeset(vision, attrs)

  # ---------------------------------------------------------------------------
  # Goals
  # ---------------------------------------------------------------------------

  def list_goals do
    Repo.all(from g in Goal, order_by: [asc: g.name])
  end

  def list_goals_for_vision(vision_id) do
    Repo.all(from g in Goal, where: g.vision_id == ^vision_id, order_by: [asc: g.name])
  end

  def get_goal!(id), do: Repo.get!(Goal, id)

  def create_goal(attrs \\ %{}) do
    %Goal{}
    |> Goal.changeset(attrs)
    |> Repo.insert()
  end

  def update_goal(%Goal{} = goal, attrs) do
    goal
    |> Goal.changeset(attrs)
    |> Repo.update()
  end

  def delete_goal(%Goal{} = goal), do: Repo.delete(goal)

  def change_goal(%Goal{} = goal, attrs \\ %{}), do: Goal.changeset(goal, attrs)

  # ---------------------------------------------------------------------------
  # Projects
  # ---------------------------------------------------------------------------

  def list_projects do
    Repo.all(from p in Project, order_by: [asc: p.name])
  end

  def list_projects_with_owner do
    Repo.all(
      from p in Project,
        order_by: [asc: p.name],
        preload: [:owner]
    )
  end

  def list_projects_for_goal(goal_id) do
    Repo.all(from p in Project, where: p.goal_id == ^goal_id, order_by: [asc: p.name])
  end

  def list_active_projects do
    Repo.all(from p in Project, where: p.status == :active, order_by: [asc: p.name])
  end

  def list_active_projects_with_owner do
    Repo.all(
      from p in Project,
        where: p.status == :active,
        order_by: [asc: p.name],
        preload: [:owner]
    )
  end

  def get_project!(id), do: Repo.get!(Project, id)

  def get_project_with_details!(id) do
    Repo.get!(Project, id)
    |> Repo.preload([:goal, :owner, :milestones, project_members: [:user]])
  end

  def create_project(attrs \\ %{}) do
    %Project{}
    |> Project.changeset(attrs)
    |> Repo.insert()
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project), do: Repo.delete(project)

  def change_project(%Project{} = project, attrs \\ %{}), do: Project.changeset(project, attrs)

  @doc """
  Locks the project baseline: marks all current features as `is_baseline: true`
  and records the lock timestamp. After this point, new features added are
  considered scope additions (drift tracking).
  """
  def lock_baseline(%Project{} = project) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      from(f in Agency.Delivery.Feature, where: f.project_id == ^project.id)
      |> Repo.update_all(set: [is_baseline: true])

      cost = Agency.Delivery.estimate_project_cost(project.id)

      project
      |> Project.changeset(%{baseline_locked_at: now, baseline_cost: cost})
      |> Repo.update!()
    end)
  end

  # ---------------------------------------------------------------------------
  # Project Members
  # ---------------------------------------------------------------------------

  def list_project_members(project_id) do
    Repo.all(
      from pm in ProjectMember,
        where: pm.project_id == ^project_id,
        join: u in assoc(pm, :user),
        order_by: [asc: u.name],
        preload: [user: u]
    )
  end

  def add_project_member(attrs \\ %{}) do
    %ProjectMember{}
    |> ProjectMember.changeset(attrs)
    |> Repo.insert()
  end

  def update_project_member(%ProjectMember{} = pm, attrs) do
    pm
    |> ProjectMember.changeset(attrs)
    |> Repo.update()
  end

  def remove_project_member(%ProjectMember{} = pm), do: Repo.delete(pm)

  def get_project_member!(id), do: Repo.get!(ProjectMember, id)

  def change_project_member(%ProjectMember{} = pm, attrs \\ %{}) do
    ProjectMember.changeset(pm, attrs)
  end

  # ---------------------------------------------------------------------------
  # Milestones
  # ---------------------------------------------------------------------------

  def list_milestones(project_id) do
    Repo.all(
      from m in Milestone,
        where: m.project_id == ^project_id,
        order_by: [asc: m.due_date]
    )
  end

  @doc "Returns milestones for a project with deliverables preloaded, ordered by due_date."
  def list_milestones_with_deliverables(project_id) do
    Repo.all(
      from m in Milestone,
        where: m.project_id == ^project_id,
        order_by: [asc: m.due_date],
        preload: [deliverables: ^from(d in Deliverable, order_by: [asc: d.due_date])]
    )
  end

  def get_milestone!(id), do: Repo.get!(Milestone, id)

  def get_milestone_with_deliverables!(id) do
    Repo.get!(Milestone, id) |> Repo.preload(:deliverables)
  end

  def create_milestone(attrs \\ %{}) do
    %Milestone{}
    |> Milestone.changeset(attrs)
    |> Repo.insert()
  end

  def update_milestone(%Milestone{} = milestone, attrs) do
    milestone
    |> Milestone.changeset(attrs)
    |> Repo.update()
  end

  def delete_milestone(%Milestone{} = milestone), do: Repo.delete(milestone)

  def change_milestone(%Milestone{} = milestone, attrs \\ %{}) do
    Milestone.changeset(milestone, attrs)
  end

  # ---------------------------------------------------------------------------
  # Deliverables
  # ---------------------------------------------------------------------------

  def list_deliverables(project_id) do
    Repo.all(
      from d in Deliverable,
        where: d.project_id == ^project_id,
        order_by: [asc: d.due_date]
    )
  end

  def list_deliverables_for_milestone(milestone_id) do
    Repo.all(
      from d in Deliverable,
        where: d.milestone_id == ^milestone_id,
        order_by: [asc: d.due_date]
    )
  end

  def get_deliverable!(id), do: Repo.get!(Deliverable, id)

  def create_deliverable(attrs \\ %{}) do
    %Deliverable{}
    |> Deliverable.changeset(attrs)
    |> Repo.insert()
  end

  def update_deliverable(%Deliverable{} = deliverable, attrs) do
    deliverable
    |> Deliverable.changeset(attrs)
    |> Repo.update()
  end

  def delete_deliverable(%Deliverable{} = deliverable), do: Repo.delete(deliverable)

  def change_deliverable(%Deliverable{} = deliverable, attrs \\ %{}) do
    Deliverable.changeset(deliverable, attrs)
  end
end
