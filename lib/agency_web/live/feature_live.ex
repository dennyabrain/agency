defmodule AgencyWeb.FeatureLive do
  use AgencyWeb, :live_view

  alias Agency.{Delivery, Sprints, Accounts, Teams, Authorization}

  alias AgencyWeb.ProjectLive.{
    FeatureFormComponent,
    TaskFormComponent
  }

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user
    feature = Delivery.get_feature_with_details!(id)

    socket =
      socket
      |> assign(:feature, feature)
      |> assign(:sprints, Sprints.list_sprints())
      |> assign(:all_users, Accounts.list_users())
      |> assign(:page_title, feature.name)
      |> assign(:editing_feature, nil)
      |> assign(:editing_task, nil)
      |> assign(:editing_task_feature_id, nil)
      |> assign(:can_edit, Authorization.can_create_project?(user))
      |> assign(:can_assign, Authorization.can_assign_members?(user))
      |> assign(:can_view_cost, Authorization.can_view_project_cost?(user))
      |> assign(:can_view_salary, Authorization.can_view_salary?(user))

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # handle_event
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("open_feature_form", _params, socket) do
    {:noreply, assign(socket, :editing_feature, socket.assigns.feature)}
  end

  def handle_event("close_feature_form", _params, socket) do
    {:noreply, assign(socket, :editing_feature, nil)}
  end

  def handle_event("open_task_form", %{"feature-id" => fid} = params, socket) do
    task =
      case Map.get(params, "task-id") do
        nil ->
          nil

        tid ->
          socket.assigns.feature.tasks |> Enum.find(&(&1.id == tid))
      end

    {:noreply, socket |> assign(:editing_task, task) |> assign(:editing_task_feature_id, fid)}
  end

  def handle_event("close_task_form", _params, socket) do
    {:noreply, socket |> assign(:editing_task, nil) |> assign(:editing_task_feature_id, nil)}
  end

  def handle_event("update_task_status", %{"id" => id, "status" => status}, socket) do
    task = socket.assigns.feature.tasks |> Enum.find(&(&1.id == id))

    case Delivery.update_task(task, %{status: status}) do
      {:ok, _} ->
        {:noreply, reload_feature(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update task status.")}
    end
  end

  def handle_event("add_resource", %{"url" => url} = params, socket) when url != "" do
    attrs = %{
      url: String.trim(url),
      title: params |> Map.get("title", "") |> String.trim() |> nilify(),
      kind: Map.get(params, "kind", "website"),
      feature_id: socket.assigns.feature.id
    }

    case Delivery.create_resource(attrs) do
      {:ok, _} ->
        {:noreply, reload_feature(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add resource. Check the URL.")}
    end
  end

  def handle_event("add_resource", _params, socket), do: {:noreply, socket}

  def handle_event("remove_resource", %{"id" => id}, socket) do
    Delivery.delete_resource(id)
    {:noreply, reload_feature(socket)}
  end

  def handle_event("add_team_member", %{"user_id" => user_id}, socket) when user_id != "" do
    feature = socket.assigns.feature

    with {:ok, team_id} <- ensure_team(feature),
         {:ok, _} <- Teams.add_team_member(%{team_id: team_id, user_id: user_id}) do
      {:noreply, reload_feature(socket)}
    else
      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add team member.")}
    end
  end

  def handle_event("add_team_member", _params, socket), do: {:noreply, socket}

  def handle_event("remove_team_member", %{"id" => tm_id}, socket) do
    tm = Teams.get_team_member!(tm_id)
    Teams.remove_team_member(tm)
    {:noreply, reload_feature(socket)}
  end

  # ---------------------------------------------------------------------------
  # handle_info (from child LiveComponents)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:feature_saved, _feature}, socket) do
    {:noreply, socket |> reload_feature() |> assign(:editing_feature, nil)}
  end

  def handle_info({:task_saved, _task}, socket) do
    {:noreply,
     socket
     |> reload_feature()
     |> assign(:editing_task, nil)
     |> assign(:editing_task_feature_id, nil)}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp reload_feature(socket) do
    assign(socket, :feature, Delivery.get_feature_with_details!(socket.assigns.feature.id))
  end

  defp ensure_team(%{team_id: team_id}) when not is_nil(team_id), do: {:ok, team_id}

  defp ensure_team(feature) do
    case Teams.create_team(%{name: "#{feature.name} Team"}) do
      {:ok, team} ->
        case Delivery.update_feature(feature, %{team_id: team.id}) do
          {:ok, _} -> {:ok, team.id}
          err -> err
        end

      err ->
        err
    end
  end

  defp team_members(%{team: %{team_members: members}}), do: members
  defp team_members(_), do: []

  defp assignable_users(all_users, feature) do
    existing_ids = team_members(feature) |> Enum.map(& &1.user_id)
    Enum.reject(all_users, &(&1.id in existing_ids))
  end

  defp done_count(tasks), do: Enum.count(tasks, &(&1.status == :done))

  defp nilify(""), do: nil
  defp nilify(s), do: s

  defp status_color(:backlog), do: "bg-zinc-100 text-zinc-600"
  defp status_color(:in_progress), do: "bg-blue-100 text-blue-700"
  defp status_color(:completed), do: "bg-emerald-100 text-emerald-700"
  defp status_color(:cancelled), do: "bg-red-100 text-red-600"
  defp status_color(_), do: "bg-zinc-100 text-zinc-600"

  defp task_status_color(:todo), do: "bg-zinc-100 text-zinc-600"
  defp task_status_color(:in_progress), do: "bg-blue-100 text-blue-700"
  defp task_status_color(:in_review), do: "bg-amber-100 text-amber-700"
  defp task_status_color(:done), do: "bg-emerald-100 text-emerald-700"
  defp task_status_color(:blocked), do: "bg-red-100 text-red-600"
  defp task_status_color(_), do: "bg-zinc-100 text-zinc-600"

  defp kind_label(:github), do: "GitHub"
  defp kind_label(:gdoc), do: "Google Doc"
  defp kind_label(:gsheet), do: "Google Sheet"
  defp kind_label(:figma), do: "Figma"
  defp kind_label(:notion), do: "Notion"
  defp kind_label(:website), do: "Link"
  defp kind_label(:other), do: "Other"
  defp kind_label(_), do: "Link"

  defp kind_color(:github), do: "bg-zinc-800 text-white"
  defp kind_color(:gdoc), do: "bg-blue-100 text-blue-700"
  defp kind_color(:gsheet), do: "bg-emerald-100 text-emerald-700"
  defp kind_color(:figma), do: "bg-violet-100 text-violet-700"
  defp kind_color(:notion), do: "bg-zinc-100 text-zinc-700"
  defp kind_color(_), do: "bg-zinc-100 text-zinc-500"

  defp resource_display_title(r) do
    if r.title && r.title != "", do: r.title, else: r.url
  end

  defp format_feature_cost(feature_id) do
    cost = Delivery.estimate_feature_cost(feature_id)

    if Decimal.compare(cost, Decimal.new(0)) == :eq,
      do: "—",
      else: "$#{Decimal.round(cost, 0)}"
  end

  defp task_statuses, do: ~w(todo in_progress in_review done blocked)

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :team_members, team_members(assigns.feature))

    ~H"""
    <div class="max-w-3xl mx-auto space-y-8">
      <%!-- Back link --%>
      <div>
        <.link
          navigate={~p"/projects/#{@feature.project_id}/plan"}
          class="inline-flex items-center gap-1 text-sm text-zinc-500 hover:text-zinc-800"
        >
          <.icon name="hero-arrow-left-mini" class="h-4 w-4" />
          {@feature.project.name}
        </.link>
      </div>

      <%!-- Header --%>
      <div class="flex items-start justify-between gap-4">
        <div class="space-y-1 min-w-0">
          <div class="flex items-center gap-3 flex-wrap">
            <h1 class="text-2xl font-bold text-zinc-900">{@feature.name}</h1>
            <span class={[
              "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
              status_color(@feature.status)
            ]}>
              {Phoenix.Naming.humanize(@feature.status)}
            </span>
            <span
              :if={@feature.is_baseline == false && !is_nil(@feature.id)}
              class="inline-flex items-center rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700"
            >
              Scope +
            </span>
          </div>
          <div class="flex items-center gap-4 text-sm text-zinc-500 flex-wrap">
            <span :if={@feature.sprint}>
              Sprint {@feature.sprint.number}
              <span class="text-zinc-400">
                ({Calendar.strftime(@feature.sprint.start_date, "%b %d")}
                – {Calendar.strftime(@feature.sprint.end_date, "%b %d")})
              </span>
            </span>
            <span :if={!@feature.sprint} class="italic text-zinc-400">Unscheduled</span>
            <span class="text-zinc-400">{done_count(@feature.tasks)}/{length(@feature.tasks)} tasks done</span>
          </div>
        </div>
        <.button :if={@can_edit} phx-click="open_feature_form" class="shrink-0">
          Edit
        </.button>
      </div>

      <%!-- Description / Hypothesis --%>
      <div :if={@feature.description || @feature.hypothesis} class="space-y-2 text-sm text-zinc-600">
        <p :if={@feature.description}>{@feature.description}</p>
        <p :if={@feature.hypothesis} class="italic text-zinc-500">
          Hypothesis: {@feature.hypothesis}
        </p>
      </div>

      <%!-- Tasks --%>
      <div>
        <div class="flex items-center justify-between mb-3">
          <h2 class="text-base font-semibold text-zinc-900">
            Tasks
            <span class="ml-1 text-sm font-normal text-zinc-500">
              ({length(@feature.tasks)})
            </span>
          </h2>
          <.button
            :if={@can_edit}
            phx-click={JS.push("open_task_form", value: %{"feature-id": @feature.id})}
            class="text-xs py-1 px-3"
          >
            + Add task
          </.button>
        </div>

        <div
          :if={@feature.tasks != []}
          class="rounded-lg border border-zinc-200 bg-white divide-y divide-zinc-100"
        >
          <div :for={task <- @feature.tasks} class="flex items-center justify-between px-4 py-3">
            <div class="flex items-center gap-2 min-w-0">
              <span class="text-sm text-zinc-800 truncate">{task.name}</span>
              <span :if={task.estimated_hours} class="text-xs text-zinc-400">
                {task.estimated_hours}h
              </span>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <span :if={length(task.resources) > 0} class="text-xs text-zinc-400">
                {length(task.resources)} link{if length(task.resources) != 1, do: "s"}
              </span>
              <span :if={task.assignee} class="text-xs text-zinc-400">{task.assignee.name}</span>
              <select
                phx-change="update_task_status"
                name="status"
                phx-value-id={task.id}
                class="text-xs rounded border-zinc-300 py-0.5"
              >
                <option
                  :for={s <- task_statuses()}
                  value={s}
                  selected={s == to_string(task.status)}
                >
                  {Phoenix.Naming.humanize(s)}
                </option>
              </select>
              <.button
                :if={@can_edit}
                phx-click={
                  JS.push("open_task_form",
                    value: %{"feature-id": @feature.id, "task-id": task.id}
                  )
                }
                class="text-xs py-0.5 px-2"
              >
                Edit
              </.button>
            </div>
          </div>
        </div>

        <p :if={@feature.tasks == []} class="text-sm text-zinc-400 py-2">No tasks yet.</p>
      </div>

      <%!-- Resources --%>
      <div>
        <h2 class="text-base font-semibold text-zinc-900 mb-3">Resources</h2>

        <div :if={@feature.resources != []} class="flex flex-wrap gap-2 mb-3">
          <div
            :for={r <- @feature.resources}
            class="group flex items-center gap-1.5 rounded-full bg-white border border-zinc-200 pl-2 pr-1 py-1 text-xs"
          >
            <span class={["rounded-full px-1.5 py-0.5 text-xs font-medium", kind_color(r.kind)]}>
              {kind_label(r.kind)}
            </span>
            <a
              href={r.url}
              target="_blank"
              rel="noopener noreferrer"
              class="text-zinc-700 hover:text-zinc-900 hover:underline max-w-48 truncate"
            >
              {resource_display_title(r)}
            </a>
            <button
              :if={@can_edit}
              phx-click="remove_resource"
              phx-value-id={r.id}
              class="text-zinc-300 hover:text-red-500 leading-none ml-0.5"
              aria-label="Remove"
            >
              ×
            </button>
          </div>
        </div>

        <form
          :if={@can_edit}
          phx-submit="add_resource"
          class="flex items-center gap-2 flex-wrap"
        >
          <input
            type="url"
            name="url"
            placeholder="https://…"
            class="flex-1 min-w-40 text-sm rounded border-zinc-300 py-1 px-2"
            required
          />
          <input
            type="text"
            name="title"
            placeholder="Label (optional)"
            class="w-36 text-sm rounded border-zinc-300 py-1 px-2"
          />
          <select name="kind" class="text-sm rounded border-zinc-300 py-1">
            <option value="website">Link</option>
            <option value="github">GitHub</option>
            <option value="gdoc">Google Doc</option>
            <option value="gsheet">Google Sheet</option>
            <option value="figma">Figma</option>
            <option value="notion">Notion</option>
            <option value="other">Other</option>
          </select>
          <.button type="submit" class="text-xs py-1 px-3">Add</.button>
        </form>
      </div>

      <%!-- Feature team --%>
      <div :if={@can_assign || @team_members != []}>
        <h2 class="text-base font-semibold text-zinc-900 mb-3">Feature team</h2>

        <div :if={@team_members != []} class="flex flex-wrap gap-2 mb-3">
          <div
            :for={tm <- @team_members}
            class="flex items-center gap-1.5 rounded-full bg-white border border-zinc-200 px-3 py-1 text-xs"
          >
            <span class="font-medium text-zinc-700">{tm.user.name}</span>
            <span class="text-zinc-400">{Phoenix.Naming.humanize(tm.user.discipline)}</span>
            <button
              :if={@can_assign}
              phx-click="remove_team_member"
              phx-value-id={tm.id}
              class="ml-1 text-zinc-300 hover:text-red-500 leading-none"
              aria-label="Remove"
            >
              ×
            </button>
          </div>
        </div>

        <form :if={@can_assign} phx-submit="add_team_member" class="flex items-center gap-2">
          <select name="user_id" class="text-sm rounded border-zinc-300 py-1">
            <option value="">Add team member…</option>
            <option
              :for={u <- assignable_users(@all_users, @feature)}
              value={u.id}
            >
              {u.name} — {Phoenix.Naming.humanize(u.discipline)}
            </option>
          </select>
          <.button type="submit" class="text-xs py-1 px-3">Add</.button>
        </form>
      </div>

      <%!-- Cost --%>
      <div :if={@can_view_cost} class="rounded-lg border border-zinc-200 bg-zinc-50 p-4">
        <p class="text-sm text-zinc-500 mb-1">Estimated cost</p>
        <p class="text-2xl font-bold text-zinc-900">{format_feature_cost(@feature.id)}</p>
      </div>

      <%!-- Edit feature modal --%>
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
          project_id={@feature.project_id}
          sprints={@sprints}
          current_user={@current_user}
        />
      </.modal>

      <%!-- Task form modal --%>
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
end
