defmodule AgencyWeb.WeeklyNotesLive do
  use AgencyWeb, :live_view

  alias Agency.Delivery

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    week_start = parse_week_start(params["week"])
    tasks = Delivery.tasks_for_week(week_start)
    markdown = generate_markdown(week_start, tasks)

    {:noreply,
     socket
     |> assign(:week_start, week_start)
     |> assign(:markdown, markdown)
     |> assign(:page_title, "Weekly Notes")}
  end

  @impl true
  def handle_event("prev_week", _params, socket) do
    new_start = Date.add(socket.assigns.week_start, -7)
    {:noreply, push_patch(socket, to: ~p"/weekly-notes?week=#{Date.to_iso8601(new_start)}")}
  end

  def handle_event("next_week", _params, socket) do
    new_start = Date.add(socket.assigns.week_start, 7)
    {:noreply, push_patch(socket, to: ~p"/weekly-notes?week=#{Date.to_iso8601(new_start)}")}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp parse_week_start(nil), do: current_week_start()
  defp parse_week_start(str) do
    case Date.from_iso8601(str) do
      {:ok, date} -> monday_of(date)
      _ -> current_week_start()
    end
  end

  defp current_week_start, do: monday_of(Date.utc_today())

  defp monday_of(date) do
    # Date.day_of_week returns 1 (Mon) … 7 (Sun)
    days_since_monday = Date.day_of_week(date) - 1
    Date.add(date, -days_since_monday)
  end

  defp week_end(week_start), do: Date.add(week_start, 6)

  defp format_date(date), do: Calendar.strftime(date, "%d %b %Y")

  defp generate_markdown(week_start, []) do
    week_end = week_end(week_start)
    "# Week of #{format_date(week_start)} – #{format_date(week_end)}\n\n_No task activity recorded this week._\n"
  end

  defp generate_markdown(week_start, tasks) do
    week_end = week_end(week_start)
    header = "# Week of #{format_date(week_start)} – #{format_date(week_end)}\n"

    # Group: project → feature → [tasks]
    by_project =
      tasks
      |> Enum.group_by(& &1.feature.project)
      |> Enum.sort_by(fn {project, _} -> project.name end)

    sections =
      Enum.map(by_project, fn {project, project_tasks} ->
        by_feature =
          project_tasks
          |> Enum.group_by(& &1.feature)
          |> Enum.sort_by(fn {feature, _} -> feature.name end)

        feature_sections =
          Enum.map(by_feature, fn {feature, feature_tasks} ->
            # Feature assignees = unique assignees across its tasks
            assignees =
              feature_tasks
              |> Enum.flat_map(fn t -> Enum.map(t.task_assignees, & &1.assignee.name) end)
              |> Enum.uniq()
              |> Enum.sort()

            feature_resources = format_resources(feature.resources)

            task_lines =
              Enum.map(feature_tasks, fn task ->
                assignee_str =
                  case task.task_assignees do
                    [] -> ""
                    tas -> " _(#{Enum.map_join(tas, ", ", & &1.assignee.name)})_"
                  end

                total_hours = Enum.sum(Enum.map(task.task_assignees, & &1.estimated_hours))

                hours_str =
                  if total_hours > 0, do: " · #{total_hours}h", else: ""

                status_badge = status_icon(task.status)
                task_resources = format_resources(task.resources)

                line = "    - #{status_badge} **#{task.name}**#{assignee_str}#{hours_str}"

                if task_resources != "" do
                  line <> "\n      " <> task_resources
                else
                  line
                end
              end)

            assignee_line =
              if assignees != [], do: "\n  _Team: #{Enum.join(assignees, ", ")}_", else: ""

            resource_line =
              if feature_resources != "", do: "\n  #{feature_resources}", else: ""

            """
              - ### #{feature.name}#{assignee_line}#{resource_line}
            #{Enum.join(task_lines, "\n")}
            """
          end)

        "## #{project.name}\n\n#{Enum.join(feature_sections, "\n")}"
      end)

    header <> "\n" <> Enum.join(sections, "\n---\n\n")
  end

  defp status_icon(:todo), do: "☐"
  defp status_icon(:in_progress), do: "▶"
  defp status_icon(:in_review), do: "⏳"
  defp status_icon(:done), do: "✓"
  defp status_icon(:blocked), do: "✗"
  defp status_icon(_), do: "·"

  defp format_resources([]), do: ""
  defp format_resources(nil), do: ""
  defp format_resources(resources) do
    links =
      Enum.map(resources, fn r ->
        label = if r.title && r.title != "", do: r.title, else: kind_label(r.kind)
        "[#{label}](#{r.url})"
      end)
    "Resources: " <> Enum.join(links, " · ")
  end

  defp kind_label(:github), do: "GitHub"
  defp kind_label(:gdoc), do: "Google Doc"
  defp kind_label(:gsheet), do: "Google Sheet"
  defp kind_label(:figma), do: "Figma"
  defp kind_label(:notion), do: "Notion"
  defp kind_label(:website), do: "Link"
  defp kind_label(:other), do: "Resource"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header + week navigation --%>
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-xl font-semibold text-zinc-900">Weekly Notes</h1>
          <p class="text-sm text-zinc-500 mt-0.5">
            {format_date(@week_start)} – {format_date(week_end(@week_start))}
          </p>
        </div>
        <div class="flex items-center gap-2">
          <button
            phx-click="prev_week"
            class="rounded border border-zinc-300 px-3 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50"
          >
            ← Previous
          </button>
          <button
            phx-click="next_week"
            class="rounded border border-zinc-300 px-3 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50"
          >
            Next →
          </button>
        </div>
      </div>

      <%!-- Markdown output + copy button --%>
      <div class="space-y-2">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-zinc-700">Generated markdown</span>
          <button
            id="copy-btn"
            phx-hook="CopyMarkdown"
            data-target="markdown-output"
            class="rounded border border-zinc-300 px-3 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-50"
          >
            Copy
          </button>
        </div>
        <textarea
          id="markdown-output"
          readonly
          rows="30"
          class="w-full rounded-md border border-zinc-300 bg-zinc-50 p-3 font-mono text-sm text-zinc-800 focus:outline-none"
        >{@markdown}</textarea>
      </div>
    </div>
    """
  end
end
