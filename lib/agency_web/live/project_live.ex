defmodule AgencyWeb.ProjectLive do
  use AgencyWeb, :live_view

  alias Agency.{Planning, Delivery, Sprints, Accounts, Authorization}

  alias AgencyWeb.ProjectLive.{
    ProjectFormComponent,
    FeatureFormComponent,
    TaskFormComponent,
    FeatureComponent,
    MemberPanelComponent
  }

  # ---------------------------------------------------------------------------
  # mount / handle_params
  # ---------------------------------------------------------------------------

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    project = Planning.get_project_with_details!(id)
    features = Delivery.list_features_with_details(id)

    socket =
      socket
      |> assign(:project, project)
      |> assign(:features, features)
      |> assign(:sprints, Sprints.list_sprints())
      |> assign(:all_users, Accounts.list_users())
      |> assign(:expanded_feature_id, nil)
      |> assign(:editing_feature, nil)
      |> assign(:editing_task, nil)
      |> assign(:editing_task_feature_id, nil)
      |> assign(:can_edit, Authorization.can_create_project?(user))
      |> assign(:can_assign, Authorization.can_assign_members?(user))
      |> assign(:can_view_cost, Authorization.can_view_project_cost?(user))
      |> assign(:can_view_salary, Authorization.can_view_salary?(user))

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :plan, _params) do
    assign(socket, :page_title, "#{socket.assigns.project.name} · Plan")
  end

  defp apply_action(socket, :track, _params) do
    project = socket.assigns.project

    workload = Delivery.workload_by_project(project.id)
    milestones = Planning.list_milestones(project.id)

    current_cost =
      if socket.assigns.can_view_cost, do: Delivery.estimate_project_cost(project.id)

    baseline_cost =
      if socket.assigns.can_view_cost && project.baseline_locked_at do
        Delivery.estimate_project_cost(project.id, only_baseline: true)
      end

    socket
    |> assign(:page_title, "#{project.name} · Track")
    |> assign(:workload, workload)
    |> assign(:milestones, milestones)
    |> assign(:current_cost, current_cost)
    |> assign(:baseline_cost, baseline_cost)
  end

  # ---------------------------------------------------------------------------
  # handle_event
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_feature", %{"id" => feature_id}, socket) do
    expanded =
      if socket.assigns.expanded_feature_id == feature_id, do: nil, else: feature_id

    {:noreply, assign(socket, :expanded_feature_id, expanded)}
  end

  def handle_event("open_feature_form", %{"id" => id}, socket) do
    feature = Enum.find(socket.assigns.features, &(&1.id == id))
    {:noreply, assign(socket, :editing_feature, feature)}
  end

  def handle_event("open_feature_form", _params, socket) do
    {:noreply, assign(socket, :editing_feature, %Delivery.Feature{})}
  end

  def handle_event("close_feature_form", _params, socket) do
    {:noreply, assign(socket, :editing_feature, nil)}
  end

  def handle_event("close_task_form", _params, socket) do
    {:noreply, socket |> assign(:editing_task, nil) |> assign(:editing_task_feature_id, nil)}
  end

  def handle_event("open_task_form", %{"feature-id" => fid} = params, socket) do
    task =
      case Map.get(params, "task-id") do
        nil -> nil
        tid ->
          socket.assigns.features
          |> Enum.flat_map(& &1.tasks)
          |> Enum.find(&(&1.id == tid))
      end

    {:noreply, socket |> assign(:editing_task, task) |> assign(:editing_task_feature_id, fid)}
  end

  def handle_event("lock_baseline", _params, socket) do
    if socket.assigns.can_edit do
      case Planning.lock_baseline(socket.assigns.project) do
        {:ok, updated_project} ->
          project = Planning.get_project_with_details!(updated_project.id)

          {:noreply,
           socket
           |> assign(:project, project)
           |> put_flash(:info, "Baseline locked. Scope drift tracking is now active.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to lock baseline.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
  end

  def handle_event("update_feature_status", %{"id" => id, "status" => status}, socket) do
    feature = Enum.find(socket.assigns.features, &(&1.id == id))

    case Delivery.update_feature(feature, %{status: status}) do
      {:ok, _} ->
        features = Delivery.list_features_with_details(socket.assigns.project.id)
        {:noreply, assign(socket, :features, features)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update feature status.")}
    end
  end

  def handle_event("update_task_status", %{"id" => id, "status" => status}, socket) do
    task =
      socket.assigns.features
      |> Enum.flat_map(& &1.tasks)
      |> Enum.find(&(&1.id == id))

    case Delivery.update_task(task, %{status: status}) do
      {:ok, _} ->
        features = Delivery.list_features_with_details(socket.assigns.project.id)
        {:noreply, assign(socket, :features, features)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update task status.")}
    end
  end

  # ---------------------------------------------------------------------------
  # handle_info (from child LiveComponents)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:project_saved, project}, socket) do
    socket =
      socket
      |> assign(:project, Planning.get_project_with_details!(project.id))
      |> put_flash(:info, "Project updated.")
      |> push_event("js-hide-modal", %{id: "project-form-modal"})

    {:noreply, socket}
  end

  def handle_info({:feature_saved, _feature}, socket) do
    features = Delivery.list_features_with_details(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:features, features)
     |> assign(:editing_feature, nil)}
  end

  def handle_info({:task_saved, _task}, socket) do
    features = Delivery.list_features_with_details(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:features, features)
     |> assign(:editing_task, nil)
     |> assign(:editing_task_feature_id, nil)}
  end

  def handle_info({:member_changed, _}, socket) do
    project = Planning.get_project_with_details!(socket.assigns.project.id)
    {:noreply, assign(socket, :project, project)}
  end

  # ---------------------------------------------------------------------------
  # render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Project header --%>
      <div class="flex items-start justify-between mb-6">
        <div>
          <div class="flex items-center gap-3">
            <h1 class="text-2xl font-bold text-zinc-900">{@project.name}</h1>
            <.status_badge status={@project.status} />
          </div>
          <p :if={@project.objective} class="mt-1 text-sm text-zinc-500">{@project.objective}</p>
          <p class="mt-1 text-xs text-zinc-400">
            <span :if={@project.start_date}>
              {Calendar.strftime(@project.start_date, "%b %d, %Y")}
            </span>
            <span :if={@project.start_date && @project.end_date}> → </span>
            <span :if={@project.end_date}>
              {Calendar.strftime(@project.end_date, "%b %d, %Y")}
            </span>
          </p>
        </div>
        <div class="flex items-center gap-2">
          <.button
            :if={@can_edit}
            phx-click={show_modal("project-form-modal")}
            class="btn-secondary"
          >
            Edit
          </.button>
        </div>
      </div>

      <%!-- Page tabs --%>
      <div class="flex gap-1 border-b border-zinc-200 mb-8">
        <.link
          patch={~p"/projects/#{@project.id}/plan"}
          class={tab_class(@live_action == :plan)}
        >
          Plan
        </.link>
        <.link
          patch={~p"/projects/#{@project.id}/track"}
          class={tab_class(@live_action == :track)}
        >
          Track
        </.link>
      </div>

      <%!-- Tab content --%>
      <%= if @live_action == :plan do %>
        <.plan_tab
          project={@project}
          features={@features}
          sprints={@sprints}
          all_users={@all_users}
          expanded_feature_id={@expanded_feature_id}
          editing_feature={@editing_feature}
          editing_task={@editing_task}
          editing_task_feature_id={@editing_task_feature_id}
          can_edit={@can_edit}
          can_assign={@can_assign}
          can_view_cost={@can_view_cost}
          can_view_salary={@can_view_salary}
          current_user={@current_user}
        />
      <% end %>

      <%= if @live_action == :track do %>
        <.track_tab
          project={@project}
          features={@features}
          milestones={assigns[:milestones] || []}
          workload={assigns[:workload] || []}
          current_cost={assigns[:current_cost]}
          baseline_cost={assigns[:baseline_cost]}
          editing_task={@editing_task}
          editing_task_feature_id={@editing_task_feature_id}
          can_view_cost={@can_view_cost}
          all_users={@all_users}
          current_user={@current_user}
        />
      <% end %>

      <%!-- Shared modals --%>
      <.modal id="project-form-modal">
        <.live_component
          module={ProjectFormComponent}
          id="project-form"
          project={@project}
          all_users={@all_users}
          current_user={@current_user}
        />
      </.modal>

      <.modal
        :if={@editing_feature}
        id="feature-form-modal"
        show
        on_cancel={JS.push("close_feature_form")}
      >
        <.live_component
          module={FeatureFormComponent}
          id="feature-form"
          feature={@editing_feature}
          project_id={@project.id}
          sprints={@sprints}
          current_user={@current_user}
        />
      </.modal>

      <.modal
        :if={@editing_task_feature_id}
        id="task-form-modal"
        show
        on_cancel={JS.push("close_task_form")}
      >
        <.live_component
          module={TaskFormComponent}
          id="task-form"
          task={@editing_task}
          feature_id={@editing_task_feature_id}
          all_users={@all_users}
          current_user={@current_user}
        />
      </.modal>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Plan tab
  # ---------------------------------------------------------------------------

  defp plan_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Baseline actions --%>
      <div class="flex items-center gap-4">
        <.button
          :if={!@project.baseline_locked_at && @can_edit}
          phx-click="lock_baseline"
          data-confirm="Lock the baseline? All current features will be marked as baseline. You can still add features after, but they'll be tracked as scope additions."
        >
          Lock Baseline
        </.button>

        <div
          :if={@project.baseline_locked_at}
          class="flex items-center gap-2 text-sm text-emerald-700 bg-emerald-50 rounded-lg px-3 py-1.5"
        >
          <.icon name="hero-lock-closed-mini" class="h-4 w-4" />
          Baseline locked {Calendar.strftime(@project.baseline_locked_at, "%b %d, %Y")}
        </div>
      </div>

      <%!-- Features --%>
      <div>
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-base font-semibold text-zinc-900">
            Features
            <span class="ml-1 text-sm font-normal text-zinc-500">({length(@features)})</span>
          </h2>
          <.button
            :if={@can_edit}
            phx-click="open_feature_form"
          >
            + Add Feature
          </.button>
        </div>

        <div class="divide-y divide-zinc-100 rounded-lg border border-zinc-200 bg-white">
          <.live_component
            :for={feature <- @features}
            module={FeatureComponent}
            id={"feature-#{feature.id}"}
            feature={feature}
            is_expanded={@expanded_feature_id == feature.id}
            all_users={@all_users}
            can_edit={@can_edit}
            can_assign={@can_assign}
            can_view_cost={@can_view_cost}
            can_view_salary={@can_view_salary}
            current_user={@current_user}
          />

          <div :if={@features == []} class="px-4 py-8 text-center text-sm text-zinc-400">
            No features yet. Add the first one to start planning.
          </div>
        </div>
      </div>

      <%!-- Project members --%>
      <.live_component
        module={MemberPanelComponent}
        id="member-panel"
        project={@project}
        all_users={@all_users}
        can_assign={@can_assign}
        can_view_salary={@can_view_salary}
      />

      <%!-- Cost summary --%>
      <div :if={@can_view_cost} class="rounded-lg border border-zinc-200 bg-zinc-50 p-4">
        <h2 class="text-sm font-semibold text-zinc-700 mb-1">Cost estimate</h2>
        <p class="text-2xl font-bold text-zinc-900">
          {format_cost(Delivery.estimate_project_cost(@project.id))}
        </p>
        <p :if={@project.baseline_locked_at} class="text-xs text-zinc-500 mt-1">
          Baseline: {format_cost(Delivery.estimate_project_cost(@project.id, only_baseline: true))}
        </p>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Track tab
  # ---------------------------------------------------------------------------

  defp track_tab(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Scope drift banner --%>
      <div
        :if={@can_view_cost && @baseline_cost && @current_cost}
        class="rounded-lg border border-zinc-200 bg-white p-4"
      >
        <h2 class="text-sm font-semibold text-zinc-700 mb-2">Scope drift</h2>
        <div class="flex gap-8 text-sm">
          <div>
            <p class="text-zinc-500">Baseline cost</p>
            <p class="text-lg font-semibold text-zinc-900">{format_cost(@baseline_cost)}</p>
          </div>
          <div>
            <p class="text-zinc-500">Current cost</p>
            <p class={["text-lg font-semibold", drift_color(@baseline_cost, @current_cost)]}>
              {format_cost(@current_cost)}
            </p>
          </div>
          <div>
            <p class="text-zinc-500">Drift</p>
            <p class={["text-lg font-semibold", drift_color(@baseline_cost, @current_cost)]}>
              {format_cost(Decimal.sub(@current_cost, @baseline_cost))}
            </p>
          </div>
        </div>
      </div>

      <%!-- Milestones --%>
      <div :if={@milestones != []}>
        <h2 class="text-base font-semibold text-zinc-900 mb-3">Milestones</h2>
        <div class="divide-y divide-zinc-100 rounded-lg border border-zinc-200 bg-white">
          <div :for={m <- @milestones} class="flex items-center justify-between px-4 py-3">
            <div>
              <p class="text-sm font-medium text-zinc-900">{m.name}</p>
              <p :if={m.due_date} class="text-xs text-zinc-500">
                Due {Calendar.strftime(m.due_date, "%b %d, %Y")}
              </p>
            </div>
            <.status_badge status={m.status} />
          </div>
        </div>
      </div>

      <%!-- Features Kanban board --%>
      <div>
        <h2 class="text-base font-semibold text-zinc-900 mb-3">Features</h2>
        <div class="overflow-x-auto">
          <div class="grid grid-cols-4 gap-3" style="min-width: 640px;">
            <%= for {status, label, header_class} <- kanban_columns() do %>
              <% group = Enum.filter(@features, &(to_string(&1.status) == status)) %>
              <div class="flex flex-col">
                <div class="flex items-center justify-between mb-2 px-1">
                  <h3 class={"text-xs font-semibold uppercase tracking-wide " <> header_class}>
                    {label}
                  </h3>
                  <span class="text-xs text-zinc-400 font-medium">{length(group)}</span>
                </div>
                <div class="flex flex-col gap-2 min-h-28 rounded-lg bg-zinc-50 p-2">
                  <div
                    :for={f <- group}
                    class="rounded-md border border-zinc-200 bg-white p-3 shadow-sm space-y-2"
                  >
                    <.link
                      navigate={~p"/features/#{f.id}"}
                      class="text-sm font-medium text-zinc-900 hover:underline leading-snug"
                    >
                      {f.name}
                    </.link>
                    <div class="flex items-center justify-between gap-2">
                      <span class="text-xs text-zinc-400 shrink-0">
                        {done_count(f.tasks)}/{length(f.tasks)} done
                      </span>
                      <select
                        phx-change="update_feature_status"
                        name="status"
                        phx-value-id={f.id}
                        class="text-xs rounded border-zinc-300 py-0.5 min-w-0"
                      >
                        <option
                          :for={s <- feature_statuses()}
                          value={s}
                          selected={s == to_string(f.status)}
                        >
                          {Phoenix.Naming.humanize(s)}
                        </option>
                      </select>
                    </div>
                    <p :if={f.sprint} class="text-xs text-zinc-400">Sprint {f.sprint.number}</p>
                  </div>
                  <div
                    :if={group == []}
                    class="flex-1 rounded-md border border-dashed border-zinc-200 py-6 text-center text-xs text-zinc-300"
                  >
                    Empty
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Workload table --%>
      <div :if={@can_view_cost && @workload != []}>
        <h2 class="text-base font-semibold text-zinc-900 mb-3">Workload</h2>
        <.table id="workload" rows={@workload}>
          <:col :let={w} label="Team member">{w.user_name}</:col>
          <:col :let={w} label="Discipline">{Phoenix.Naming.humanize(w.discipline)}</:col>
          <:col :let={w} label="Tasks">{w.task_count}</:col>
          <:col :let={w} label="Estimated hours">{w.total_estimated_hours || 0}</:col>
        </.table>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp tab_class(active) do
    base = "px-4 py-2 text-sm font-medium border-b-2 -mb-px "

    if active do
      base <> "border-zinc-900 text-zinc-900"
    else
      base <> "border-transparent text-zinc-500 hover:text-zinc-700 hover:border-zinc-300"
    end
  end

  defp status_badge(assigns) do
    ~H"""
    <span class={["inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium", status_color(@status)]}>
      {Phoenix.Naming.humanize(@status)}
    </span>
    """
  end

  defp status_color(:draft), do: "bg-zinc-100 text-zinc-600"
  defp status_color(:pending), do: "bg-zinc-100 text-zinc-600"
  defp status_color(:active), do: "bg-emerald-100 text-emerald-700"
  defp status_color(:in_progress), do: "bg-blue-100 text-blue-700"
  defp status_color(:backlog), do: "bg-zinc-100 text-zinc-600"
  defp status_color(:completed), do: "bg-emerald-100 text-emerald-700"
  defp status_color(:cancelled), do: "bg-red-100 text-red-600"
  defp status_color(:on_hold), do: "bg-amber-100 text-amber-700"
  defp status_color(:archived), do: "bg-zinc-100 text-zinc-400"
  defp status_color(_), do: "bg-zinc-100 text-zinc-600"

  defp format_cost(nil), do: "—"
  defp format_cost(%Decimal{} = d), do: "$#{Decimal.round(d, 0)}"
  defp format_cost(0), do: "$0"

  defp kanban_columns do
    [
      {"backlog", "Backlog", "text-zinc-500"},
      {"in_progress", "In Progress", "text-blue-600"},
      {"completed", "Completed", "text-emerald-600"},
      {"cancelled", "Cancelled", "text-red-500"}
    ]
  end

  defp done_count(tasks), do: Enum.count(tasks, &(&1.status == :done))

  defp feature_statuses, do: ~w(backlog in_progress completed cancelled)
  defp task_statuses, do: ~w(todo in_progress in_review done blocked)

  defp drift_color(baseline, current) do
    if Decimal.compare(current, baseline) == :gt, do: "text-red-600", else: "text-emerald-600"
  end
end
