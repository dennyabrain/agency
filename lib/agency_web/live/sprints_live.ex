defmodule AgencyWeb.SprintsLive do
  use AgencyWeb, :live_view

  alias Agency.{Sprints, Planning, Delivery, Authorization}
  alias Agency.Sprints.Sprint

  @row_height 60
  @feature_row_height 44

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    sprints = Sprints.list_sprints()
    projects = Planning.list_projects_with_owner()
    features_by_project = features_by_project()

    {:ok,
     socket
     |> assign(:sprints, sprints)
     |> assign(:projects, projects)
     |> assign(:chart, build_chart(sprints, projects, features_by_project))
     |> assign(:row_height, @row_height)
     |> assign(:feature_row_height, @feature_row_height)
     |> assign(:expanded_project_ids, MapSet.new())
     |> assign(:can_manage, Authorization.can_create_project?(user))
     |> assign(:form, nil)
     |> assign(:editing_sprint, nil)
     |> assign(:page_title, "Sprints")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params),
    do: assign(socket, form: nil, editing_sprint: nil)

  defp apply_action(socket, :new, _params) do
    sprint = %Sprint{number: Sprints.next_sprint_number()}
    assign(socket, editing_sprint: sprint, form: build_form(sprint))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    sprint = Sprints.get_sprint!(id)
    assign(socket, editing_sprint: sprint, form: build_form(sprint))
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_project", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded_project_ids

    new_expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, :expanded_project_ids, new_expanded)}
  end

  def handle_event("validate", %{"sprint" => params}, socket) do
    changeset =
      socket.assigns.editing_sprint
      |> Sprints.change_sprint(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: "sprint"))}
  end

  def handle_event("save", %{"sprint" => params}, socket) do
    sprint = socket.assigns.editing_sprint

    result =
      if sprint.id,
        do: Sprints.update_sprint(sprint, params),
        else: Sprints.create_sprint(params)

    case result do
      {:ok, _} ->
        sprints = Sprints.list_sprints()

        {:noreply,
         socket
         |> put_flash(:info, if(sprint.id, do: "Sprint updated.", else: "Sprint created."))
         |> assign(:sprints, sprints)
         |> assign(:chart, build_chart(sprints, socket.assigns.projects, features_by_project()))
         |> push_patch(to: ~p"/sprints")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "sprint"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    sprint = Sprints.get_sprint!(id)

    case Sprints.delete_sprint(sprint) do
      {:ok, _} ->
        sprints = Sprints.list_sprints()

        {:noreply,
         socket
         |> put_flash(:info, "Sprint deleted.")
         |> assign(:sprints, sprints)
         |> assign(:chart, build_chart(sprints, socket.assigns.projects, features_by_project()))}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Cannot delete sprint — features are assigned to it.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Data helpers
  # ---------------------------------------------------------------------------

  defp features_by_project do
    Delivery.list_all_features_for_gantt()
    |> Enum.group_by(& &1.project_id)
  end

  # ---------------------------------------------------------------------------
  # Chart builder
  # ---------------------------------------------------------------------------

  defp build_chart(sprints, projects, features_by_project) do
    dated = Enum.filter(sprints, &(&1.start_date && &1.end_date))
    today = Date.utc_today()

    {rs, re, total} =
      if dated == [] do
        rs = bom(today)
        re = eom(Date.add(today, 89))
        {rs, re, max(Date.diff(re, rs) + 1, 1)}
      else
        all_dates = Enum.flat_map(dated, &[&1.start_date, &1.end_date])
        min_d = Enum.min([today | all_dates], Date)
        max_d = Enum.max([today | all_dates], Date)
        rs = bom(min_d)
        re = eom(max_d)
        {rs, re, max(Date.diff(re, rs) + 1, 1)}
      end

    today_in_range = Date.compare(today, rs) != :lt and Date.compare(today, re) != :gt

    sprint_cols =
      Enum.map(dated, fn s ->
        %{
          sprint: s,
          label: sprint_col_label(s),
          date_range: "#{Calendar.strftime(s.start_date, "%b %d")} – #{Calendar.strftime(s.end_date, "%b %d")}",
          left_pct: dpct(s.start_date, rs, total),
          width_pct: dspan_pct(s.start_date, s.end_date, total),
          status: sprint_status(s)
        }
      end)

    project_rows =
      projects
      |> Enum.reject(&(&1.status == :archived))
      |> Enum.map(&build_project_row(&1, features_by_project, rs, total))

    %{
      sprint_cols: sprint_cols,
      project_rows: project_rows,
      today_pct: if(today_in_range, do: dpct(today, rs, total)),
      min_chart_width: max(600, length(sprint_cols) * 140)
    }
  end

  defp build_project_row(project, features_by_project, rs, total) do
    all_features = Map.get(features_by_project, project.id, [])

    sprint_features =
      Enum.filter(all_features, fn f ->
        f.sprint && f.sprint.start_date && f.sprint.end_date
      end)

    {bar_left, bar_right} =
      if sprint_features == [] do
        {nil, nil}
      else
        l = Enum.min_by(sprint_features, & &1.sprint.start_date, Date).sprint.start_date
        r = Enum.max_by(sprint_features, & &1.sprint.end_date, Date).sprint.end_date
        {l, r}
      end

    feature_rows =
      sprint_features
      |> Enum.map(fn f ->
        done = Enum.count(f.tasks, &(&1.status == :done))

        %{
          feature: f,
          sprint: f.sprint,
          task_count: length(f.tasks),
          done_count: done,
          left_pct: dpct(f.sprint.start_date, rs, total),
          width_pct: dspan_pct(f.sprint.start_date, f.sprint.end_date, total)
        }
      end)
      |> Enum.sort_by(& &1.sprint.number)

    %{
      project: project,
      feature_count: length(sprint_features),
      has_bar: bar_left != nil,
      left_pct: if(bar_left, do: dpct(bar_left, rs, total), else: 0),
      width_pct: if(bar_left && bar_right, do: dspan_pct(bar_left, bar_right, total), else: 0),
      feature_rows: feature_rows
    }
  end

  # ---------------------------------------------------------------------------
  # Formatting / colour helpers
  # ---------------------------------------------------------------------------

  defp sprint_col_label(%Sprint{number: n, name: nil}), do: "Sprint #{n}"
  defp sprint_col_label(%Sprint{number: n, name: ""}), do: "Sprint #{n}"
  defp sprint_col_label(%Sprint{number: n, name: name}), do: "S#{n} — #{name}"

  defp sprint_status(%Sprint{start_date: nil}), do: :upcoming
  defp sprint_status(%Sprint{end_date: nil}), do: :upcoming

  defp sprint_status(s) do
    today = Date.utc_today()

    cond do
      Date.compare(today, s.start_date) == :lt -> :upcoming
      Date.compare(today, s.end_date) == :gt -> :past
      true -> :current
    end
  end

  defp sprint_col_bg(:current), do: "bg-emerald-50 border-t-2 border-t-emerald-400"
  defp sprint_col_bg(:upcoming), do: "bg-blue-50/50 border-t-2 border-t-blue-300"
  defp sprint_col_bg(:past), do: "bg-zinc-50"

  defp project_bar_bg(:active), do: "bg-emerald-500"
  defp project_bar_bg(:on_hold), do: "bg-amber-400"
  defp project_bar_bg(:completed), do: "bg-blue-400"
  defp project_bar_bg(:draft), do: "bg-zinc-400"
  defp project_bar_bg(_), do: "bg-zinc-300"

  defp feature_bar_bg(:in_progress), do: "bg-amber-400"
  defp feature_bar_bg(:completed), do: "bg-emerald-400"
  defp feature_bar_bg(:cancelled), do: "bg-red-300"
  defp feature_bar_bg(_), do: "bg-zinc-300"

  defp bom(d), do: %{d | day: 1}
  defp eom(d), do: %{d | day: Date.days_in_month(d)}
  defp dpct(d, rs, t), do: Float.round(Date.diff(d, rs) / t * 100, 3)
  defp dspan_pct(s, e, t), do: Float.round((Date.diff(e, s) + 1) / t * 100, 3)

  defp build_form(s), do: Sprints.change_sprint(s) |> to_form(as: "sprint")

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">

      <%!-- Page header --%>
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-semibold text-zinc-900">Sprints</h1>
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-3 text-xs text-zinc-500">
            <span class="flex items-center gap-1.5">
              <span class="h-2.5 w-2.5 rounded-full bg-emerald-500 inline-block" /> Active
            </span>
            <span class="flex items-center gap-1.5">
              <span class="h-2.5 w-2.5 rounded-full bg-amber-400 inline-block" /> On hold
            </span>
            <span class="flex items-center gap-1.5">
              <span class="h-2.5 w-2.5 rounded-full bg-blue-400 inline-block" /> Completed
            </span>
            <span class="flex items-center gap-1.5">
              <span class="h-3 w-px bg-red-400 inline-block" /> Today
            </span>
          </div>
          <.link
            :if={@can_manage}
            patch={~p"/sprints/new"}
            class="rounded bg-zinc-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-zinc-700"
          >
            New Sprint
          </.link>
        </div>
      </div>

      <%!-- Gantt --%>
      <div class="rounded-xl border border-zinc-200 bg-white overflow-hidden flex">

        <%!-- ── Fixed left label column ── --%>
        <div class="w-56 shrink-0 border-r border-zinc-200 z-10">

          <%!-- Header spacer --%>
          <div class="h-14 bg-zinc-50 border-b border-zinc-200" />

          <%!-- Project label rows --%>
          <div :for={row <- @chart.project_rows}>

            <div
              class="flex items-center px-3 border-b border-zinc-100 bg-white"
              style={"height: #{@row_height}px"}
            >
              <button
                phx-click="toggle_project"
                phx-value-id={row.project.id}
                class="mr-2 shrink-0 w-5 h-5 flex items-center justify-center text-[10px] text-zinc-400 hover:text-zinc-600 rounded hover:bg-zinc-100 transition-transform"
                style={if MapSet.member?(@expanded_project_ids, row.project.id), do: "transform: rotate(90deg)"}
              >
                ▶
              </button>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold text-zinc-800 leading-tight truncate">
                  {row.project.name}
                </p>
                <p class="text-xs text-zinc-400 mt-0.5">
                  {row.feature_count} {if row.feature_count == 1, do: "feature", else: "features"}
                </p>
              </div>
            </div>

            <div :if={MapSet.member?(@expanded_project_ids, row.project.id)}>
              <div
                :if={row.feature_rows == []}
                class="h-10 border-b border-zinc-50 flex items-center pl-10 pr-4 bg-zinc-50"
              >
                <span class="text-xs text-zinc-400 italic">No features in any sprint</span>
              </div>
              <div
                :for={feat <- row.feature_rows}
                class="border-b border-zinc-50 flex items-center pl-9 pr-4 bg-zinc-50/50"
                style={"height: #{@feature_row_height}px"}
              >
                <span class="text-zinc-300 mr-2 text-xs select-none">└</span>
                <div class="min-w-0 flex-1">
                  <p class="text-xs font-medium text-zinc-600 truncate leading-tight">
                    {feat.feature.name}
                  </p>
                  <p class="text-[10px] text-zinc-400 mt-0.5">
                    Sprint {feat.sprint.number} · {feat.done_count}/{feat.task_count} done
                  </p>
                </div>
              </div>
            </div>

          </div>

          <%!-- Empty state labels --%>
          <div :if={@chart.sprint_cols == []} class="h-32 flex items-center px-4">
            <span class="text-sm text-zinc-400">No sprints yet</span>
          </div>
          <div :if={@chart.sprint_cols != [] && @chart.project_rows == []} class="h-32 flex items-center px-4">
            <span class="text-sm text-zinc-400">No projects</span>
          </div>

        </div>

        <%!-- ── Scrollable chart area ── --%>
        <div class="overflow-x-auto flex-1">
          <div style={"min-width: #{@chart.min_chart_width}px"}>

            <%!-- Sprint column headers --%>
            <div class="relative h-14 bg-zinc-50 border-b border-zinc-200">
              <div
                :for={col <- @chart.sprint_cols}
                style={"left: #{col.left_pct}%; width: #{col.width_pct}%;"}
                class={"absolute inset-y-0 flex flex-col justify-center px-2 border-l border-zinc-200 overflow-hidden group #{sprint_col_bg(col.status)}"}
              >
                <span class="text-xs font-semibold text-zinc-700 select-none whitespace-nowrap truncate">
                  {col.label}
                </span>
                <span class="text-[10px] text-zinc-400 select-none whitespace-nowrap">
                  {col.date_range}
                </span>
                <div
                  :if={@can_manage}
                  class="absolute top-1.5 right-1.5 opacity-0 group-hover:opacity-100 flex gap-1.5 text-[10px]"
                >
                  <.link
                    patch={~p"/sprints/#{col.sprint.id}/edit"}
                    class="text-zinc-400 hover:text-zinc-700"
                  >
                    Edit
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={col.sprint.id}
                    data-confirm={"Delete Sprint #{col.sprint.number}?"}
                    class="text-red-400 hover:text-red-600"
                  >
                    Del
                  </button>
                </div>
              </div>

              <%!-- Today: pill in ruler --%>
              <div
                :if={@chart.today_pct}
                style={"left: #{@chart.today_pct}%"}
                class="absolute top-0 bottom-0 z-20 flex flex-col items-center pointer-events-none"
              >
                <div class="bg-red-400 text-white text-[9px] font-bold px-1.5 py-px rounded-b leading-tight select-none whitespace-nowrap">
                  today
                </div>
                <div class="flex-1 w-px bg-red-400/50" />
              </div>
            </div>

            <%!-- Project chart rows --%>
            <div :for={row <- @chart.project_rows}>

              <div class="relative border-b border-zinc-100" style={"height: #{@row_height}px"}>
                <div
                  :for={col <- @chart.sprint_cols}
                  style={"left: #{col.left_pct}%"}
                  class="absolute inset-y-0 border-l border-zinc-100"
                />
                <div
                  :if={@chart.today_pct}
                  style={"left: #{@chart.today_pct}%"}
                  class="absolute inset-y-0 w-px bg-red-400/50 z-10"
                />
                <div
                  :if={row.has_bar}
                  style={"top: 12px; left: #{row.left_pct}%; width: max(#{row.width_pct}%, 48px);"}
                  class={"absolute h-9 rounded-lg flex items-center overflow-hidden select-none #{project_bar_bg(row.project.status)}"}
                >

                </div>
                <div :if={!row.has_bar} class="absolute inset-0 flex items-center px-4">
                  <span class="text-xs text-zinc-300 italic">No sprints assigned</span>
                </div>
              </div>

              <div :if={MapSet.member?(@expanded_project_ids, row.project.id)}>
                <div
                  :if={row.feature_rows == []}
                  class="h-10 border-b border-zinc-50 bg-zinc-50"
                />
                <div
                  :for={feat <- row.feature_rows}
                  class="relative border-b border-zinc-50 bg-zinc-50/50"
                  style={"height: #{@feature_row_height}px"}
                >
                  <div
                    :for={col <- @chart.sprint_cols}
                    style={"left: #{col.left_pct}%"}
                    class="absolute inset-y-0 border-l border-zinc-100"
                  />
                  <div
                    :if={@chart.today_pct}
                    style={"left: #{@chart.today_pct}%"}
                    class="absolute inset-y-0 w-px bg-red-400/40 z-10"
                  />
                  <.link
                    navigate={~p"/features/#{feat.feature.id}"}
                    style={"top: 8px; left: #{feat.left_pct}%; width: max(#{feat.width_pct}%, 40px);"}
                    class={"absolute block h-7 rounded-md flex items-center overflow-hidden hover:brightness-90 transition-[filter] #{feature_bar_bg(feat.feature.status)}"}
                  >

                  </.link>
                </div>
              </div>

            </div>

            <%!-- Empty: no sprints --%>
            <div
              :if={@chart.sprint_cols == []}
              class="h-32 flex items-center justify-center text-sm text-zinc-400"
            >
              Create your first sprint to see the Gantt chart
            </div>

            <%!-- Empty: sprints but no projects --%>
            <div
              :if={@chart.sprint_cols != [] && @chart.project_rows == []}
              class="relative h-32"
            >
              <div
                :for={col <- @chart.sprint_cols}
                style={"left: #{col.left_pct}%"}
                class="absolute inset-y-0 border-l border-zinc-100"
              />
            </div>

          </div>
        </div>

      </div>

      <%!-- Create / edit sprint modal --%>
      <.modal
        :if={@live_action in [:new, :edit]}
        id="sprint-modal"
        show
        on_cancel={JS.patch(~p"/sprints")}
      >
        <.header>
          {if @live_action == :new,
            do: "New Sprint",
            else: "Edit Sprint #{@editing_sprint.number}"}
        </.header>

        <.simple_form for={@form} id="sprint-form" phx-change="validate" phx-submit="save">
          <div class="grid grid-cols-2 gap-4">
            <.input field={@form[:number]} type="number" label="Sprint number" min="1" required />
            <.input field={@form[:name]} type="text" label="Name (optional)" />
          </div>
          <div class="grid grid-cols-2 gap-4">
            <.input field={@form[:start_date]} type="date" label="Start date" required />
            <.input field={@form[:end_date]} type="date" label="End date" required />
          </div>
          <:actions>
            <.button phx-disable-with="Saving...">
              {if @live_action == :new, do: "Create sprint", else: "Update sprint"}
            </.button>
          </:actions>
        </.simple_form>
      </.modal>

    </div>
    """
  end
end
