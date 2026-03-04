defmodule AgencyWeb.WorkloadLive do
  use AgencyWeb, :live_view

  alias Agency.{Delivery, Planning}

  @impl true
  def mount(_params, _session, socket) do
    raw_data = Delivery.workload_by_month()
    projects = Planning.list_active_projects_with_owner()

    socket =
      socket
      |> assign(:page_title, "Team Workload")
      |> assign(:raw_data, raw_data)
      |> assign(:projects, projects)
      |> assign(:selected_project_id, nil)
      |> build_matrix(raw_data, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project_id" => project_id}, socket) do
    project_id = if project_id == "", do: nil, else: project_id

    {:noreply,
     socket
     |> assign(:selected_project_id, project_id)
     |> build_matrix(socket.assigns.raw_data, project_id)}
  end

  # ---------------------------------------------------------------------------
  # Matrix builder — pure in-memory aggregation, no extra DB queries
  # ---------------------------------------------------------------------------

  defp build_matrix(socket, raw_data, project_id) do
    filtered =
      if project_id,
        do: Enum.filter(raw_data, &(&1.project_id == project_id)),
        else: raw_data

    months =
      filtered
      |> Enum.map(& &1.month)
      |> Enum.uniq()
      |> Enum.sort()

    users =
      filtered
      |> Enum.map(fn r -> {r.user_id, r.user_name, r.discipline} end)
      |> Enum.uniq_by(fn {id, _, _} -> id end)
      |> Enum.sort_by(fn {_, name, _} -> name end)

    # {user_id, month} -> total_hours
    matrix =
      Enum.reduce(filtered, %{}, fn row, acc ->
        key = {row.user_id, row.month}
        Map.update(acc, key, row.total_hours || 0, &(&1 + (row.total_hours || 0)))
      end)

    # month -> total_hours (column totals)
    column_totals =
      Enum.reduce(filtered, %{}, fn row, acc ->
        Map.update(acc, row.month, row.total_hours || 0, &(&1 + (row.total_hours || 0)))
      end)

    # user_id -> total_hours (row totals)
    row_totals =
      Enum.reduce(filtered, %{}, fn row, acc ->
        Map.update(acc, row.user_id, row.total_hours || 0, &(&1 + (row.total_hours || 0)))
      end)

    grand_total = filtered |> Enum.map(&(&1.total_hours || 0)) |> Enum.sum()

    socket
    |> assign(:months, months)
    |> assign(:users, users)
    |> assign(:matrix, matrix)
    |> assign(:column_totals, column_totals)
    |> assign(:row_totals, row_totals)
    |> assign(:grand_total, grand_total)
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Team Workload
        <:subtitle>Estimated hours per person per month</:subtitle>
        <:actions>
          <select
            phx-change="filter_project"
            name="project_id"
            class="text-sm rounded border-zinc-300 py-1.5 pr-8"
          >
            <option value="">All projects</option>
            <option :for={p <- @projects} value={p.id} selected={p.id == @selected_project_id}>
              {p.name}
            </option>
          </select>
        </:actions>
      </.header>

      <%!-- Empty state --%>
      <div
        :if={@users == []}
        class="mt-10 text-center text-zinc-400 text-sm"
      >
        No workload data yet. Assign team members to tasks with estimated hours to see workload here.
      </div>

      <%!-- Workload matrix --%>
      <div :if={@users != []} class="mt-6 overflow-x-auto rounded-lg border border-zinc-200">
        <table class="min-w-full text-sm">
          <thead>
            <tr class="bg-zinc-50 border-b border-zinc-200">
              <th class="sticky left-0 z-10 bg-zinc-50 px-4 py-3 text-left font-semibold text-zinc-700 whitespace-nowrap min-w-48">
                Team member
              </th>
              <th class="px-4 py-3 text-left font-semibold text-zinc-500 whitespace-nowrap">
                Discipline
              </th>
              <th
                :for={month <- @months}
                class="px-4 py-3 text-center font-semibold text-zinc-700 whitespace-nowrap min-w-24"
              >
                {format_month(month)}
              </th>
              <th class="px-4 py-3 text-center font-semibold text-zinc-900 whitespace-nowrap bg-zinc-100">
                Total
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-100 bg-white">
            <tr :for={{user_id, user_name, discipline} <- @users} class="hover:bg-zinc-50">
              <td class="sticky left-0 z-10 bg-white px-4 py-3 font-medium text-zinc-800 whitespace-nowrap hover:bg-zinc-50">
                {user_name}
              </td>
              <td class="px-4 py-3 text-zinc-500 whitespace-nowrap">
                {Phoenix.Naming.humanize(discipline)}
              </td>
              <td :for={month <- @months} class="px-2 py-2 text-center">
                <.hours_cell hours={Map.get(@matrix, {user_id, month}, 0)} />
              </td>
              <td class="px-4 py-3 text-center font-semibold text-zinc-800 bg-zinc-50 whitespace-nowrap">
                {Map.get(@row_totals, user_id, 0)}h
              </td>
            </tr>
          </tbody>
          <tfoot>
            <tr class="border-t-2 border-zinc-200 bg-zinc-50">
              <td
                colspan="2"
                class="sticky left-0 z-10 bg-zinc-50 px-4 py-3 font-semibold text-zinc-700"
              >
                Total
              </td>
              <td :for={month <- @months} class="px-4 py-3 text-center font-semibold text-zinc-800 whitespace-nowrap">
                {Map.get(@column_totals, month, 0)}h
              </td>
              <td class="px-4 py-3 text-center font-bold text-zinc-900 bg-zinc-100 whitespace-nowrap">
                {@grand_total}h
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      <%!-- Legend --%>
      <div :if={@users != []} class="mt-4 flex items-center gap-4 text-xs text-zinc-500">
        <span>Load per month:</span>
        <span class="flex items-center gap-1">
          <span class="inline-block w-3 h-3 rounded-sm bg-zinc-100"></span> 0h
        </span>
        <span class="flex items-center gap-1">
          <span class="inline-block w-3 h-3 rounded-sm bg-emerald-100"></span> 1–40h
        </span>
        <span class="flex items-center gap-1">
          <span class="inline-block w-3 h-3 rounded-sm bg-emerald-200"></span> 41–80h
        </span>
        <span class="flex items-center gap-1">
          <span class="inline-block w-3 h-3 rounded-sm bg-amber-100"></span> 81–120h
        </span>
        <span class="flex items-center gap-1">
          <span class="inline-block w-3 h-3 rounded-sm bg-orange-100"></span> 121–160h
        </span>
        <span class="flex items-center gap-1">
          <span class="inline-block w-3 h-3 rounded-sm bg-red-100"></span> &gt;160h
        </span>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  defp hours_cell(assigns) do
    ~H"""
    <div
      :if={@hours > 0}
      class={["rounded px-2 py-1 text-xs font-medium tabular-nums text-center", cell_color(@hours)]}
    >
      {@hours}h
    </div>
    <div :if={@hours == 0} class="text-zinc-300 text-xs text-center">—</div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp format_month(%Date{year: year, month: month}) do
    month_abbr = ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec) |> Enum.at(month - 1)
    "#{month_abbr} #{year}"
  end

  defp format_month(_), do: "—"

  defp cell_color(hours) when hours == 0, do: "bg-zinc-100 text-zinc-400"
  defp cell_color(hours) when hours <= 40, do: "bg-emerald-100 text-emerald-800"
  defp cell_color(hours) when hours <= 80, do: "bg-emerald-200 text-emerald-900"
  defp cell_color(hours) when hours <= 120, do: "bg-amber-100 text-amber-800"
  defp cell_color(hours) when hours <= 160, do: "bg-orange-100 text-orange-800"
  defp cell_color(_), do: "bg-red-100 text-red-800"
end
