defmodule AgencyWeb.DashboardLive do
  use AgencyWeb, :live_view

  alias Agency.{Planning, Delivery, Authorization}

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    projects = Planning.list_projects_with_owner()

    projects_with_cost =
      if Authorization.can_view_project_cost?(user) do
        Enum.map(projects, fn p ->
          Map.put(p, :estimated_cost, Delivery.estimate_project_cost(p.id))
        end)
      else
        Enum.map(projects, fn p -> Map.put(p, :estimated_cost, nil) end)
      end

    feature_counts =
      Map.new(projects, fn p ->
        {p.id, length(Delivery.list_features(p.id))}
      end)

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:projects, projects_with_cost)
      |> assign(:feature_counts, feature_counts)
      |> assign(:can_create_project, Authorization.can_create_project?(user))
      |> assign(:can_view_cost, Authorization.can_view_project_cost?(user))

    {:ok, socket}
  end

  def handle_info({:project_saved, project}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/projects/#{project.id}/plan")}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Dashboard
        <:subtitle>All active projects</:subtitle>
        <:actions>
          <.button
            :if={@can_create_project}
            phx-click={show_modal("project-form-modal")}
          >
            New Project
          </.button>
        </:actions>
      </.header>

      <.table id="projects" rows={@projects}>
        <:col :let={p} label="Project">
          <.link navigate={~p"/projects/#{p.id}/plan"} class="font-medium text-zinc-900 hover:underline">
            {p.name}
          </.link>
        </:col>
        <:col :let={p} label="Status">
          <.status_badge status={p.status} />
        </:col>
        <:col :let={p} label="Owner">
          {if p.owner, do: p.owner.name, else: "—"}
        </:col>
        <:col :let={p} label="Features">
          {Map.get(@feature_counts, p.id, 0)}
        </:col>
        <:col :let={p} label="Cost estimate">
          <span :if={@can_view_cost && p.estimated_cost}>
            {format_cost(p.estimated_cost)}
          </span>
          <span :if={!@can_view_cost} class="text-zinc-400">—</span>
        </:col>
        <:col :let={p} label="End date">
          {if p.end_date, do: Calendar.strftime(p.end_date, "%b %d, %Y"), else: "—"}
        </:col>
        <:action :let={p}>
          <.link navigate={~p"/projects/#{p.id}/plan"} class="text-sm font-medium">
            Plan
          </.link>
        </:action>
        <:action :let={p}>
          <.link navigate={~p"/projects/#{p.id}/track"} class="text-sm font-medium">
            Track
          </.link>
        </:action>
      </.table>

      <p :if={@projects == []} class="mt-8 text-center text-zinc-500">
        No active projects yet.
        <span :if={@can_create_project}>
          <button phx-click={show_modal("project-form-modal")} class="text-zinc-700 underline">
            Create one.
          </button>
        </span>
      </p>

      <.modal :if={@can_create_project} id="project-form-modal">
        <.live_component
          module={AgencyWeb.ProjectLive.ProjectFormComponent}
          id="project-form"
          project={nil}
          all_users={Agency.Accounts.list_users()}
          current_user={@current_user}
        />
      </.modal>
    </div>
    """
  end

  defp format_cost(decimal) do
    decimal
    |> Decimal.round(0)
    |> Decimal.to_string()
    |> then(&"$#{&1}")
  end

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
      status_color(@status)
    ]}>
      {Phoenix.Naming.humanize(@status)}
    </span>
    """
  end

  defp status_color(:draft), do: "bg-zinc-100 text-zinc-600"
  defp status_color(:active), do: "bg-emerald-100 text-emerald-700"
  defp status_color(:on_hold), do: "bg-amber-100 text-amber-700"
  defp status_color(:completed), do: "bg-blue-100 text-blue-700"
  defp status_color(:archived), do: "bg-zinc-100 text-zinc-400"
  defp status_color(_), do: "bg-zinc-100 text-zinc-600"
end
