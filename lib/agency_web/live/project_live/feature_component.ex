defmodule AgencyWeb.ProjectLive.FeatureComponent do
  use AgencyWeb, :live_component

  alias Agency.Delivery

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  # ---------------------------------------------------------------------------
  # handle_event — resources
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("add_resource", %{"url" => url} = params, socket) when url != "" do
    attrs = %{
      url: String.trim(url),
      title: params |> Map.get("title", "") |> String.trim() |> nilify(),
      kind: Map.get(params, "kind", "website"),
      feature_id: socket.assigns.feature.id
    }

    case Delivery.create_resource(attrs) do
      {:ok, _} ->
        send(self(), {:feature_saved, socket.assigns.feature})
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add resource. Check the URL.")}
    end
  end

  def handle_event("add_resource", _params, socket), do: {:noreply, socket}

  def handle_event("remove_resource", %{"id" => id}, socket) do
    Delivery.delete_resource(id)
    send(self(), {:feature_saved, socket.assigns.feature})
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp nilify(""), do: nil
  defp nilify(s), do: s

  defp task_count(tasks), do: length(tasks)
  defp done_count(tasks), do: Enum.count(tasks, &(&1.status == :done))

  defp derived_team(feature) do
    feature.tasks
    |> Enum.flat_map(& &1.task_assignees)
    |> Enum.map(& &1.assignee)
    |> Enum.filter(& &1)
    |> Enum.uniq_by(& &1.id)
  end

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

  # ---------------------------------------------------------------------------
  # render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :derived_team, derived_team(assigns.feature))

    ~H"""
    <div class="feature-row">
      <%!-- Collapsed header row --%>
      <div
        class="flex items-center justify-between px-4 py-3 cursor-pointer hover:bg-zinc-50 select-none"
        phx-click="toggle_feature"
        phx-value-id={@feature.id}
      >
        <div class="flex items-center gap-3 min-w-0">
          <.icon
            name={if @is_expanded, do: "hero-chevron-down-mini", else: "hero-chevron-right-mini"}
            class="h-4 w-4 flex-shrink-0 text-zinc-400"
          />
          <span class="text-sm font-medium text-zinc-900 truncate">{@feature.name}</span>

          <span
            :if={!@feature.is_baseline && @feature.id}
            class="inline-flex items-center rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700"
          >
            Scope +
          </span>
        </div>

        <div class="flex items-center gap-3 flex-shrink-0 ml-4">
          <span :if={@feature.sprint} class="text-xs text-zinc-400">
            Sprint {@feature.sprint.number}
          </span>

          <span class="text-xs text-zinc-500">
            {done_count(@feature.tasks)}/{task_count(@feature.tasks)}
          </span>

          <span :if={length(@feature.resources) > 0} class="text-xs text-zinc-400">
            {length(@feature.resources)} link{if length(@feature.resources) != 1, do: "s"}
          </span>

          <span class={[
            "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
            status_color(@feature.status)
          ]}>
            {Phoenix.Naming.humanize(@feature.status)}
          </span>

          <.button
            :if={@can_edit}
            phx-click={JS.push("open_feature_form", value: %{id: @feature.id})}
            class="text-xs py-0.5 px-2"
          >
            Edit
          </.button>
        </div>
      </div>

      <%!-- Expanded panel --%>
      <div :if={@is_expanded} class="border-t border-zinc-100 bg-zinc-50 px-6 py-4 space-y-5">
        <%!-- Description / hypothesis --%>
        <div :if={@feature.description || @feature.hypothesis} class="space-y-2 text-sm text-zinc-600">
          <p :if={@feature.description}>{@feature.description}</p>
          <p :if={@feature.hypothesis} class="italic text-zinc-500">
            Hypothesis: {@feature.hypothesis}
          </p>
        </div>

        <%!-- Tasks --%>
        <div>
          <div class="flex items-center justify-between mb-2">
            <h4 class="text-xs font-semibold uppercase tracking-wide text-zinc-500">Tasks</h4>
            <.button
              :if={@can_edit}
              phx-click={JS.push("open_task_form", value: %{"feature-id": @feature.id})}
              class="text-xs py-0.5 px-2"
            >
              + Add task
            </.button>
          </div>

          <div :if={@feature.tasks != []} class="rounded-lg border border-zinc-200 bg-white divide-y divide-zinc-100">
            <div :for={task <- @feature.tasks} class="flex items-center justify-between px-3 py-2">
              <div class="flex items-center gap-2 min-w-0">
                <span class="text-sm text-zinc-800 truncate">{task.name}</span>
                <span :if={task.task_assignees != []} class="text-xs text-zinc-400">
                  {Enum.sum(Enum.map(task.task_assignees, & &1.estimated_hours))}h
                </span>
              </div>
              <div class="flex items-center gap-2 flex-shrink-0">
                <span :if={length(task.resources) > 0} class="text-xs text-zinc-400">
                  {length(task.resources)} link{if length(task.resources) != 1, do: "s"}
                </span>
                <span :if={task.task_assignees != []} class="text-xs text-zinc-400">
                  {Enum.map_join(task.task_assignees, ", ", & &1.assignee && &1.assignee.name)}
                </span>
                <span class={[
                  "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                  task_status_color(task.status)
                ]}>
                  {Phoenix.Naming.humanize(task.status)}
                </span>
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

          <p :if={@feature.tasks == []} class="text-xs text-zinc-400 py-2">
            No tasks yet.
          </p>
        </div>

        <%!-- Feature resources --%>
        <div>
          <h4 class="text-xs font-semibold uppercase tracking-wide text-zinc-500 mb-2">Resources</h4>

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
                phx-target={@myself}
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
            phx-target={@myself}
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

        <%!-- Owner + derived team --%>
        <div :if={@feature.owner || @derived_team != []}>
          <h4 class="text-xs font-semibold uppercase tracking-wide text-zinc-500 mb-2">
            Feature team
          </h4>

          <%!-- Owner chip --%>
          <div :if={@feature.owner} class="flex flex-wrap gap-2 mb-2">
            <div class="flex items-center gap-1.5 rounded-full bg-indigo-50 border border-indigo-200 px-3 py-1 text-xs">
              <span class="text-indigo-500 font-medium">Owner</span>
              <span class="font-medium text-zinc-700">{@feature.owner.name}</span>
              <span class="text-zinc-400">{Phoenix.Naming.humanize(@feature.owner.discipline)}</span>
            </div>
          </div>

          <%!-- Derived team (read-only) --%>
          <div :if={@derived_team != []} class="flex flex-wrap gap-2">
            <div
              :for={u <- @derived_team}
              class="flex items-center gap-1.5 rounded-full bg-white border border-zinc-200 px-3 py-1 text-xs"
            >
              <span class="font-medium text-zinc-700">{u.name}</span>
              <span class="text-zinc-400">{Phoenix.Naming.humanize(u.discipline)}</span>
            </div>
          </div>
        </div>

        <%!-- Feature cost --%>
        <div :if={@can_view_cost}>
          <p class="text-xs text-zinc-500">
            Estimated cost:
            <span class="font-semibold text-zinc-800">
              {format_feature_cost(@feature.id)}
            </span>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp format_feature_cost(feature_id) do
    cost = Delivery.estimate_feature_cost(feature_id)

    if Decimal.compare(cost, Decimal.new(0)) == :eq do
      "—"
    else
      "$#{Decimal.round(cost, 0)}"
    end
  end
end
