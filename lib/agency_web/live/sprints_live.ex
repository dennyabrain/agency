defmodule AgencyWeb.SprintsLive do
  use AgencyWeb, :live_view

  alias Agency.Sprints
  alias Agency.Sprints.Sprint
  alias Agency.Authorization

  @row_height 60
  @feature_row_height 44

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    sprints = Sprints.list_sprints_with_details()

    {:ok,
     socket
     |> assign(:sprints, sprints)
     |> assign(:chart, build_chart(sprints))
     |> assign(:row_height, @row_height)
     |> assign(:feature_row_height, @feature_row_height)
     |> assign(:expanded_sprint_ids, MapSet.new())
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
  def handle_event("toggle_sprint", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded_sprint_ids

    new_expanded =
      if MapSet.member?(expanded, id),
        do: MapSet.delete(expanded, id),
        else: MapSet.put(expanded, id)

    {:noreply, assign(socket, :expanded_sprint_ids, new_expanded)}
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
        sprints = Sprints.list_sprints_with_details()

        {:noreply,
         socket
         |> put_flash(:info, if(sprint.id, do: "Sprint updated.", else: "Sprint created."))
         |> assign(:sprints, sprints)
         |> assign(:chart, build_chart(sprints))
         |> push_patch(to: ~p"/sprints")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "sprint"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    sprint = Sprints.get_sprint!(id)

    case Sprints.delete_sprint(sprint) do
      {:ok, _} ->
        sprints = Sprints.list_sprints_with_details()

        {:noreply,
         socket
         |> put_flash(:info, "Sprint deleted.")
         |> assign(:sprints, sprints)
         |> assign(:chart, build_chart(sprints))}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Cannot delete sprint — features are assigned to it.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Chart builder
  # ---------------------------------------------------------------------------

  defp build_chart([]) do
    today = Date.utc_today()
    rs = bom(today)
    re = eom(Date.add(today, 89))
    total = max(Date.diff(re, rs) + 1, 1)

    %{sprints: [], months: build_months(rs, re, total), today_pct: dpct(today, rs, total)}
  end

  defp build_chart(sprints) do
    today = Date.utc_today()
    all_dates = Enum.flat_map(sprints, &[&1.start_date, &1.end_date])
    min_d = Enum.min([today | all_dates], Date)
    max_d = Enum.max([today | all_dates], Date)

    rs = bom(min_d)
    re = eom(max_d)
    total = max(Date.diff(re, rs) + 1, 1)

    today_in_range = Date.compare(today, rs) != :lt and Date.compare(today, re) != :gt

    rows =
      Enum.map(sprints, fn s ->
        %{
          sprint: s,
          feature_count: length(s.features),
          members: unique_members(s.features),
          feature_rows: build_feature_rows(s.features, s, rs, total),
          left_pct: dpct(s.start_date, rs, total),
          width_pct: dspan_pct(s.start_date, s.end_date, total),
          status: sprint_status(s)
        }
      end)

    %{
      sprints: rows,
      months: build_months(rs, re, total),
      today_pct: if(today_in_range, do: dpct(today, rs, total))
    }
  end

  defp build_feature_rows(features, sprint, rs, total) do
    features
    |> Enum.map(fn feature ->
      tasks = load_tasks(feature)
      dated = Enum.filter(tasks, & &1.due_date)

      {bar_start, bar_end} =
        if dated == [] do
          {sprint.start_date, sprint.end_date}
        else
          s = Enum.min_by(dated, & &1.due_date).due_date
          e = Enum.max_by(dated, & &1.due_date).due_date
          s = Enum.max([sprint.start_date, s], Date)
          e = Enum.min([sprint.end_date, e], Date)
          if Date.compare(e, s) == :lt, do: {sprint.start_date, sprint.end_date}, else: {s, e}
        end

      done = Enum.count(tasks, &(&1.status == :done))

      %{
        feature: feature,
        task_count: length(tasks),
        done_count: done,
        left_pct: dpct(bar_start, rs, total),
        width_pct: dspan_pct(bar_start, bar_end, total)
      }
    end)
    |> Enum.sort_by(& &1.feature.name)
  end

  defp load_tasks(%{tasks: %Ecto.Association.NotLoaded{}}), do: []
  defp load_tasks(%{tasks: tasks}), do: tasks

  defp build_months(rs, re, total) do
    Stream.unfold(bom(rs), fn ms ->
      if Date.compare(ms, re) == :gt do
        nil
      else
        me = eom(ms)
        as = Enum.max([ms, rs], Date)
        ae = Enum.min([me, re], Date)
        {%{label: Calendar.strftime(ms, "%b %Y"), left_pct: dpct(as, rs, total), width_pct: dspan_pct(as, ae, total)},
         Date.add(me, 1)}
      end
    end)
    |> Enum.to_list()
  end

  defp bom(d), do: %{d | day: 1}
  defp eom(d), do: %{d | day: Date.days_in_month(d)}
  defp dpct(d, rs, t), do: Float.round(Date.diff(d, rs) / t * 100, 3)
  defp dspan_pct(s, e, t), do: Float.round((Date.diff(e, s) + 1) / t * 100, 3)

  defp unique_members(features) do
    features
    |> Enum.flat_map(fn f ->
      case f.team do
        %{team_members: ms} when is_list(ms) -> Enum.map(ms, & &1.user)
        _ -> []
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)
  end

  defp user_initials(nil), do: "?"

  defp user_initials(name) do
    name |> String.split(" ", trim: true) |> Enum.take(2) |> Enum.map(&String.first/1) |> Enum.join() |> String.upcase()
  end

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

  defp bar_bg(:current), do: "bg-emerald-500"
  defp bar_bg(:upcoming), do: "bg-blue-500"
  defp bar_bg(:past), do: "bg-zinc-400"

  defp feature_bar_bg(:in_progress), do: "bg-amber-400"
  defp feature_bar_bg(:completed), do: "bg-emerald-400"
  defp feature_bar_bg(:cancelled), do: "bg-red-300"
  defp feature_bar_bg(_), do: "bg-zinc-400"

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
              <span class="h-2.5 w-5 rounded bg-emerald-500 inline-block" /> Current
            </span>
            <span class="flex items-center gap-1.5">
              <span class="h-2.5 w-5 rounded bg-blue-500 inline-block" /> Upcoming
            </span>
            <span class="flex items-center gap-1.5">
              <span class="h-2.5 w-5 rounded bg-zinc-400 inline-block" /> Past
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
      <div class="rounded-xl border border-zinc-200 bg-white overflow-hidden">
        <div class="overflow-x-auto">
          <div style="min-width: 640px">

            <%!-- ── Header row: label spacer + month ruler ── --%>
            <div class="flex">
              <div class="w-52 shrink-0 h-9 bg-zinc-50 border-b border-r border-zinc-200" />
              <div class="relative flex-1 h-9 bg-zinc-50 border-b border-zinc-200">
                <div
                  :for={month <- @chart.months}
                  style={"left: #{month.left_pct}%; width: #{month.width_pct}%"}
                  class="absolute inset-y-0 flex items-center px-2 border-l border-zinc-200"
                >
                  <span class="text-xs font-medium text-zinc-500 select-none whitespace-nowrap">
                    {month.label}
                  </span>
                </div>
                <%!-- Today: pill label in ruler --%>
                <div
                  :if={@chart.today_pct}
                  style={"left: #{@chart.today_pct}%"}
                  class="absolute top-0 bottom-0 z-20 flex flex-col items-center"
                >
                  <div class="bg-red-400 text-white text-[9px] font-bold px-1.5 py-px rounded-b leading-tight select-none whitespace-nowrap">
                    today
                  </div>
                  <div class="flex-1 w-px bg-red-400/50" />
                </div>
              </div>
            </div>

            <%!-- ── Sprint rows ── --%>
            <div :for={row <- @chart.sprints}>

              <%!-- Sprint row --%>
              <div class="flex border-b border-zinc-100">

                <%!-- Label column --%>
                <div
                  class="w-52 shrink-0 border-r border-zinc-200 flex items-center px-3 group"
                  style={"height: #{@row_height}px"}
                >
                  <button
                    phx-click="toggle_sprint"
                    phx-value-id={row.sprint.id}
                    class="mr-2 shrink-0 w-5 h-5 flex items-center justify-center text-[10px] text-zinc-400 hover:text-zinc-600 rounded hover:bg-zinc-100 transition-transform"
                    style={
                      if MapSet.member?(@expanded_sprint_ids, row.sprint.id),
                        do: "transform: rotate(90deg)"
                    }
                  >
                    ▶
                  </button>
                  <div class="min-w-0 flex-1">
                    <p class="text-sm font-semibold text-zinc-800 leading-tight">
                      Sprint {row.sprint.number}
                    </p>
                    <p :if={row.sprint.name} class="text-xs text-zinc-400 truncate mt-0.5">
                      {row.sprint.name}
                    </p>
                  </div>
                  <div :if={@can_manage} class="opacity-0 group-hover:opacity-100 flex gap-2 ml-2 shrink-0 text-xs">
                    <.link
                      patch={~p"/sprints/#{row.sprint.id}/edit"}
                      class="text-zinc-400 hover:text-zinc-700"
                    >
                      Edit
                    </.link>
                    <button
                      phx-click="delete"
                      phx-value-id={row.sprint.id}
                      data-confirm={"Delete Sprint #{row.sprint.number}?"}
                      class="text-red-400 hover:text-red-600"
                    >
                      Del
                    </button>
                  </div>
                </div>

                <%!-- Chart row --%>
                <div
                  class="relative flex-1 overflow-hidden"
                  style={"height: #{@row_height}px"}
                >
                  <div
                    :for={month <- @chart.months}
                    style={"left: #{month.left_pct}%"}
                    class="absolute inset-y-0 border-l border-zinc-100"
                  />
                  <div
                    :if={@chart.today_pct}
                    style={"left: #{@chart.today_pct}%"}
                    class="absolute inset-y-0 w-px bg-red-400/50 z-10"
                  />
                  <%!-- Sprint bar --%>
                  <div
                    style={"top: 10px; left: #{row.left_pct}%; width: max(#{row.width_pct}%, 44px);"}
                    class={"absolute h-10 rounded-lg flex items-center overflow-hidden select-none #{bar_bg(row.status)}"}
                  >
                    <div class="flex items-center gap-2 px-3 w-full overflow-hidden">
                      <span class="text-sm font-semibold text-white truncate min-w-0 flex-1">
                        {if row.sprint.name && row.sprint.name != "",
                          do: row.sprint.name,
                          else: "Sprint #{row.sprint.number}"}
                      </span>
                      <span
                        :if={row.feature_count > 0}
                        class="shrink-0 rounded-full bg-white/25 px-2 py-0.5 text-xs font-bold text-white"
                        title={"#{row.feature_count} features"}
                      >
                        {row.feature_count}
                      </span>
                      <div :if={row.members != []} class="flex -space-x-1.5 shrink-0">
                        <div
                          :for={user <- Enum.take(row.members, 5)}
                          title={user.name}
                          class="h-6 w-6 rounded-full bg-white ring-1 ring-white/40 flex items-center justify-center text-[10px] font-bold text-zinc-700"
                        >
                          {user_initials(user.name)}
                        </div>
                        <div
                          :if={length(row.members) > 5}
                          class="h-6 w-6 rounded-full bg-white/30 ring-1 ring-white/30 flex items-center justify-center text-[10px] font-bold text-white"
                        >
                          +{length(row.members) - 5}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <%!-- ── Feature rows (expanded) ── --%>
              <div :if={MapSet.member?(@expanded_sprint_ids, row.sprint.id)}>

                <%!-- Empty state --%>
                <div :if={row.feature_rows == []} class="flex border-b border-zinc-50">
                  <div class="w-52 shrink-0 border-r border-zinc-200 h-10 flex items-center pl-10 pr-4 bg-zinc-50">
                    <span class="text-xs text-zinc-400 italic">No features in this sprint</span>
                  </div>
                  <div class="flex-1 h-10 bg-zinc-50" />
                </div>

                <%!-- Feature rows --%>
                <div :for={feat <- row.feature_rows} class="flex border-b border-zinc-50">

                  <%!-- Feature label --%>
                  <div
                    class="w-52 shrink-0 border-r border-zinc-200 flex items-center pl-9 pr-4 bg-zinc-50/50"
                    style={"height: #{@feature_row_height}px"}
                  >
                    <span class="text-zinc-300 mr-2 text-xs select-none">└</span>
                    <div class="min-w-0 flex-1">
                      <p class="text-xs font-medium text-zinc-600 truncate leading-tight">
                        {feat.feature.name}
                      </p>
                      <p class="text-[10px] text-zinc-400 mt-0.5">
                        {feat.done_count}/{feat.task_count} done
                      </p>
                    </div>
                  </div>

                  <%!-- Feature chart --%>
                  <div
                    class="relative flex-1 overflow-hidden bg-zinc-50/50"
                    style={"height: #{@feature_row_height}px"}
                  >
                    <div
                      :for={month <- @chart.months}
                      style={"left: #{month.left_pct}%"}
                      class="absolute inset-y-0 border-l border-zinc-100"
                    />
                    <div
                      :if={@chart.today_pct}
                      style={"left: #{@chart.today_pct}%"}
                      class="absolute inset-y-0 w-px bg-red-400/40 z-10"
                    />
                    <%!-- Feature bar --%>
                    <div
                      style={"top: 8px; left: #{feat.left_pct}%; width: max(#{feat.width_pct}%, 40px);"}
                      class={"absolute h-7 rounded-md flex items-center overflow-hidden select-none #{feature_bar_bg(feat.feature.status)}"}
                    >
                      <div class="flex items-center gap-2 px-2 w-full overflow-hidden">
                        <span class="text-xs font-medium text-white truncate min-w-0 flex-1">
                          {feat.feature.name}
                        </span>
                        <span :if={feat.task_count > 0} class="shrink-0 text-[10px] text-white/80 whitespace-nowrap">
                          {feat.done_count}/{feat.task_count}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Empty chart state --%>
            <div :if={@chart.sprints == []} class="flex">
              <div class="w-52 shrink-0 border-r border-zinc-200 h-32 flex items-center px-4">
                <span class="text-sm text-zinc-400">No sprints yet</span>
              </div>
              <div class="flex-1 h-32 relative">
                <div
                  :for={month <- @chart.months}
                  style={"left: #{month.left_pct}%"}
                  class="absolute inset-y-0 border-l border-zinc-100"
                />
                <div class="absolute inset-0 flex items-center justify-center text-sm text-zinc-400">
                  Create your first sprint to see the Gantt chart
                </div>
              </div>
            </div>

          </div>
        </div>
      </div>

      <%!-- Create / edit modal --%>
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

        <.simple_form
          for={@form}
          id="sprint-form"
          phx-change="validate"
          phx-submit="save"
        >
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
