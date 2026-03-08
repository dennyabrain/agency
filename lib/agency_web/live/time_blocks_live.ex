defmodule AgencyWeb.TimeBlocksLive do
  use AgencyWeb, :live_view

  alias Agency.{Delivery, Planning, Sprints}

  # Working hours shown in week view (inclusive start, exclusive end)
  @view_start_hour 7
  @view_end_hour 22
  @hour_px 60

  # ---------------------------------------------------------------------------
  # Mount & params
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    projects = Planning.list_projects_with_owner()
    {:ok, assign(socket, :projects, projects)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view = if params["view"] == "month", do: :month, else: :week
    project_id = nilify(params["project"])

    anchor_date =
      case Date.from_iso8601(params["date"] || "") do
        {:ok, d} -> d
        _ -> Date.utc_today()
      end

    {from_dt, to_dt} = query_range(view, anchor_date)

    time_blocks =
      Delivery.list_time_blocks_for_calendar(
        project_id: project_id,
        from_dt: from_dt,
        to_dt: to_dt
      )

    sprints =
      Sprints.list_sprints_in_range(
        NaiveDateTime.to_date(from_dt),
        NaiveDateTime.to_date(to_dt)
      )

    calendar =
      case view do
        :week -> build_week(time_blocks, sprints, anchor_date)
        :month -> build_month(time_blocks, sprints, anchor_date)
      end

    {:noreply,
     socket
     |> assign(:page_title, "Calendar")
     |> assign(:view, view)
     |> assign(:anchor_date, anchor_date)
     |> assign(:project_id, project_id)
     |> assign(:calendar, calendar)}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("prev", _params, socket) do
    next_date = shift_date(socket.assigns.anchor_date, socket.assigns.view, -1)
    push_patch_params(socket, next_date)
  end

  def handle_event("next", _params, socket) do
    next_date = shift_date(socket.assigns.anchor_date, socket.assigns.view, 1)
    push_patch_params(socket, next_date)
  end

  def handle_event("set_view", %{"view" => view}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/time-blocks?#{build_params(socket.assigns.anchor_date, view, socket.assigns.project_id)}"
     )}
  end

  def handle_event("filter_project", %{"project_id" => project_id}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/time-blocks?#{build_params(socket.assigns.anchor_date, to_string(socket.assigns.view), nilify(project_id))}"
     )}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :view_height_px, (@view_end_hour - @view_start_hour) * @hour_px)

    ~H"""
    <div class="space-y-4">
      <%!-- Header toolbar --%>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <button
            phx-click="prev"
            class="rounded-lg border border-zinc-200 bg-white px-3 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50"
          >
            ‹
          </button>
          <span class="min-w-40 text-center text-sm font-semibold text-zinc-800">
            {@calendar.label}
          </span>
          <button
            phx-click="next"
            class="rounded-lg border border-zinc-200 bg-white px-3 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50"
          >
            ›
          </button>
        </div>

        <div class="flex items-center gap-2">
          <%!-- Project filter --%>
          <form phx-change="filter_project">
            <select
              name="project_id"
              class="text-sm rounded border-zinc-300 py-1.5 px-2 text-zinc-700"
            >
              <option value="" selected={is_nil(@project_id)}>All projects</option>
              <%= for p <- @projects do %>
                <option value={p.id} selected={@project_id == p.id}>{p.name}</option>
              <% end %>
            </select>
          </form>

          <%!-- View toggle --%>
          <div class="flex rounded-lg border border-zinc-200 overflow-hidden text-sm font-medium">
            <button
              phx-click="set_view"
              phx-value-view="week"
              class={[
                "px-3 py-1.5 transition-colors",
                if(@view == :week,
                  do: "bg-earth-900 text-white",
                  else: "bg-white text-zinc-700 hover:bg-zinc-50"
                )
              ]}
            >
              Week
            </button>
            <button
              phx-click="set_view"
              phx-value-view="month"
              class={[
                "px-3 py-1.5 border-l border-zinc-200 transition-colors",
                if(@view == :month,
                  do: "bg-earth-900 text-white",
                  else: "bg-white text-zinc-700 hover:bg-zinc-50"
                )
              ]}
            >
              Month
            </button>
          </div>
        </div>
      </div>

      <%!-- Calendar body --%>
      <%= if @view == :week do %>
        <.week_view
          calendar={@calendar}
          view_height_px={@view_height_px}
          view_start_hour={7}
          hour_px={60}
        />
      <% else %>
        <.month_view calendar={@calendar} />
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Week view component
  # ---------------------------------------------------------------------------

  defp week_view(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white overflow-hidden">
      <%!-- Day header row --%>
      <div class="flex border-b border-zinc-200">
        <div class="w-14 shrink-0 border-r border-zinc-200" />
        <div
          :for={{date, _blocks, sprint} <- @calendar.days}
          class="flex-1 border-r border-zinc-200 last:border-r-0 py-2 text-center"
        >
          <p class="text-xs text-zinc-500 uppercase">{Calendar.strftime(date, "%a")}</p>
          <p class={[
            "text-sm font-semibold mt-0.5",
            if(date == Date.utc_today(), do: "text-earth-700", else: "text-zinc-800")
          ]}>
            {date.day}
          </p>
          <p
            :if={sprint}
            class="text-[10px] text-indigo-400 font-medium mt-0.5 leading-none"
            title={sprint_label(sprint)}
          >
            S{sprint.number}
          </p>
        </div>
      </div>

      <%!-- Time grid --%>
      <div class="flex overflow-y-auto" style={"max-height: #{@view_height_px + 20}px"}>
        <%!-- Hour labels --%>
        <div class="w-14 shrink-0 border-r border-zinc-200 relative" style={"height: #{@view_height_px}px"}>
          <%= for h <- @calendar.hours do %>
            <div
              class="absolute right-2 text-xs text-zinc-400 -translate-y-2"
              style={"top: #{(h - @view_start_hour) * @hour_px}px"}
            >
              {format_hour(h)}
            </div>
          <% end %>
        </div>

        <%!-- Day columns --%>
        <div class="flex flex-1">
          <div
            :for={{date, blocks, _sprint} <- @calendar.days}
            class="flex-1 border-r border-zinc-200 last:border-r-0 relative"
            style={"height: #{@view_height_px}px"}
          >
            <%!-- Hour gridlines --%>
            <%= for h <- @calendar.hours do %>
              <div
                class="absolute inset-x-0 border-t border-zinc-100"
                style={"top: #{(h - @view_start_hour) * @hour_px}px"}
              />
            <% end %>

            <%!-- Today highlight --%>
            <div
              :if={date == Date.utc_today()}
              class="absolute inset-0 bg-earth-50 pointer-events-none"
            />

            <%!-- Time blocks --%>
            <div
              :for={tb <- blocks}
              class={[
                "absolute inset-x-1 rounded-md px-1.5 py-1 text-xs overflow-hidden cursor-default border",
                project_color_classes(tb.task.feature.project_id)
              ]}
              style={"top: #{block_top_px(tb.start_at)}px; height: #{block_height_px(tb.start_at, tb.end_at)}px; min-height: 20px"}
              title={block_tooltip(tb)}
            >
              <p class="font-medium leading-tight truncate">
                {block_title(tb)}
              </p>
              <p class="leading-tight truncate opacity-75">
                {tb.task.feature.project.name}
              </p>
              <div
                :if={tb.time_block_assignees != []}
                class="flex gap-0.5 mt-0.5 flex-wrap"
              >
                <span
                  :for={tba <- tb.time_block_assignees}
                  class="inline-flex h-4 w-4 items-center justify-center rounded-full bg-white/50 text-[9px] font-bold uppercase"
                  title={if tba.assignee, do: tba.assignee.name}
                >
                  {assignee_initials(tba.assignee)}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Month view component
  # ---------------------------------------------------------------------------

  defp month_view(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white overflow-hidden">
      <%!-- Weekday header --%>
      <div class="grid grid-cols-7 border-b border-zinc-200">
        <div
          :for={day <- ~w[Mon Tue Wed Thu Fri Sat Sun]}
          class="py-2 text-center text-xs font-medium text-zinc-500 uppercase border-r border-zinc-200 last:border-r-0"
        >
          {day}
        </div>
      </div>

      <%!-- Calendar grid (42 cells = 6 rows × 7 cols) --%>
      <div class="grid grid-cols-7">
        <div
          :for={{date, blocks, in_month?, sprint} <- @calendar.cells}
          class={[
            "min-h-24 border-r border-b border-zinc-100 last:border-r-0 p-1.5",
            if(in_month?, do: "bg-white", else: "bg-zinc-50")
          ]}
        >
          <div class="flex items-start justify-between mb-1">
            <p class={[
              "text-xs font-semibold",
              cond do
                date == Date.utc_today() ->
                  "inline-flex h-5 w-5 items-center justify-center rounded-full bg-earth-900 text-white"

                in_month? ->
                  "text-zinc-700"

                true ->
                  "text-zinc-300"
              end
            ]}>
              {date.day}
            </p>
            <span
              :if={sprint}
              class="text-[9px] font-medium text-indigo-400 leading-none mt-0.5"
              title={sprint_label(sprint)}
            >
              S{sprint.number}
            </span>
          </div>

          <div class="space-y-0.5">
            <div
              :for={tb <- Enum.take(blocks, 3)}
              class={[
                "flex items-center gap-1 rounded px-1 py-0.5 text-xs truncate",
                project_color_classes(tb.task.feature.project_id)
              ]}
              title={block_tooltip(tb)}
            >
              <span class="shrink-0 font-medium">
                {Calendar.strftime(tb.start_at, "%H:%M")}
              </span>
              <span class="truncate">{block_title(tb)}</span>
            </div>
            <p :if={length(blocks) > 3} class="text-xs text-zinc-400 px-1">
              +{length(blocks) - 3} more
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Calendar building
  # ---------------------------------------------------------------------------

  defp build_week(time_blocks, sprints, anchor_date) do
    week_start = week_start(anchor_date)
    week_end = Date.add(week_start, 6)

    days =
      for i <- 0..6 do
        date = Date.add(week_start, i)

        day_blocks =
          Enum.filter(time_blocks, fn tb ->
            NaiveDateTime.to_date(tb.start_at) == date
          end)

        {date, day_blocks, sprint_for_date(sprints, date)}
      end

    label =
      if week_start.month == week_end.month do
        "#{Calendar.strftime(week_start, "%b %d")} – #{week_end.day}, #{week_start.year}"
      else
        "#{Calendar.strftime(week_start, "%b %d")} – #{Calendar.strftime(week_end, "%b %d, %Y")}"
      end

    %{
      label: label,
      days: days,
      hours: @view_start_hour..(@view_end_hour - 1)
    }
  end

  defp build_month(time_blocks, sprints, anchor_date) do
    first_day = %{anchor_date | day: 1}
    last_day = Date.end_of_month(anchor_date)

    # Pad to Monday of first week
    padding = Date.day_of_week(first_day) - 1
    grid_start = Date.add(first_day, -padding)

    cells =
      for i <- 0..41 do
        date = Date.add(grid_start, i)

        day_blocks =
          Enum.filter(time_blocks, fn tb ->
            NaiveDateTime.to_date(tb.start_at) == date
          end)

        {date, day_blocks, date.month == anchor_date.month, sprint_for_date(sprints, date)}
      end

    # Trim trailing weeks if they're entirely outside the month
    cells =
      cells
      |> Enum.chunk_every(7)
      |> Enum.reject(fn week -> Enum.all?(week, fn {_, _, in_month?, _} -> !in_month? end) end)
      |> List.flatten()

    label = Calendar.strftime(first_day, "%B %Y")

    %{label: label, cells: cells, first_day: first_day, last_day: last_day}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp query_range(:week, anchor_date) do
    ws = week_start(anchor_date)
    we = Date.add(ws, 6)
    {NaiveDateTime.new!(ws, ~T[00:00:00]), NaiveDateTime.new!(we, ~T[23:59:59])}
  end

  defp query_range(:month, anchor_date) do
    first = %{anchor_date | day: 1}
    last = Date.end_of_month(anchor_date)
    # Include padding days outside the month
    padding_start = Date.add(first, -(Date.day_of_week(first) - 1))
    padding_end = Date.add(last, 7 - Date.day_of_week(last))
    {NaiveDateTime.new!(padding_start, ~T[00:00:00]), NaiveDateTime.new!(padding_end, ~T[23:59:59])}
  end

  defp week_start(date) do
    Date.add(date, -(Date.day_of_week(date) - 1))
  end

  defp shift_date(date, :week, direction), do: Date.add(date, direction * 7)

  defp shift_date(date, :month, direction) do
    new_month = date.month + direction

    {year, month} =
      cond do
        new_month < 1 -> {date.year - 1, 12}
        new_month > 12 -> {date.year + 1, 1}
        true -> {date.year, new_month}
      end

    %{date | year: year, month: month, day: 1}
  end

  defp build_params(anchor_date, view, project_id) do
    params = %{"date" => Date.to_iso8601(anchor_date), "view" => to_string(view)}
    if project_id, do: Map.put(params, "project", project_id), else: params
  end

  defp push_patch_params(socket, date) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/time-blocks?#{build_params(date, to_string(socket.assigns.view), socket.assigns.project_id)}"
     )}
  end

  defp block_top_px(%NaiveDateTime{} = start_at) do
    minutes = start_at.hour * 60 + start_at.minute - @view_start_hour * 60
    max(0, minutes)
  end

  defp block_height_px(%NaiveDateTime{} = start_at, %NaiveDateTime{} = end_at) do
    duration_minutes = NaiveDateTime.diff(end_at, start_at, :second) |> div(60)
    max(20, duration_minutes)
  end

  defp sprint_for_date(sprints, date) do
    Enum.find(sprints, fn s ->
      Date.compare(s.start_date, date) in [:lt, :eq] and
        Date.compare(s.end_date, date) in [:gt, :eq]
    end)
  end

  defp sprint_label(%{number: n, name: name}) when is_binary(name) and name != "",
    do: "Sprint #{n} · #{name}"

  defp sprint_label(%{number: n}), do: "Sprint #{n}"

  defp block_title(tb) do
    if tb.title && tb.title != "", do: tb.title, else: tb.task.name
  end

  defp block_tooltip(tb) do
    assignees =
      tb.time_block_assignees
      |> Enum.map(fn tba -> if tba.assignee, do: tba.assignee.name, else: "?" end)
      |> Enum.join(", ")

    base = "#{tb.task.name} — #{tb.task.feature.project.name}"
    if assignees != "", do: "#{base}\n#{assignees}", else: base
  end

  defp assignee_initials(nil), do: "?"

  defp assignee_initials(user) do
    user.name
    |> String.split()
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
  end

  defp format_hour(h) when h < 12, do: "#{h}am"
  defp format_hour(12), do: "12pm"
  defp format_hour(h), do: "#{h - 12}pm"

  # Derives a stable colour palette entry from a project_id string.
  @palettes [
    "bg-blue-100 text-blue-800 border-blue-200",
    "bg-violet-100 text-violet-800 border-violet-200",
    "bg-emerald-100 text-emerald-800 border-emerald-200",
    "bg-amber-100 text-amber-800 border-amber-200",
    "bg-rose-100 text-rose-800 border-rose-200",
    "bg-cyan-100 text-cyan-800 border-cyan-200",
    "bg-orange-100 text-orange-800 border-orange-200",
    "bg-pink-100 text-pink-800 border-pink-200"
  ]

  defp project_color_classes(project_id) when is_binary(project_id) do
    index = :erlang.phash2(project_id, length(@palettes))
    Enum.at(@palettes, index)
  end

  defp project_color_classes(_), do: "bg-zinc-100 text-zinc-800 border-zinc-200"

  defp nilify(nil), do: nil
  defp nilify(""), do: nil
  defp nilify(s), do: s
end
