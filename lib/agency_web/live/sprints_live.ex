defmodule AgencyWeb.SprintsLive do
  use AgencyWeb, :live_view

  alias Agency.Sprints
  alias Agency.Sprints.Sprint
  alias Agency.Authorization

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:sprints, Sprints.list_sprints())
     |> assign(:can_manage, Authorization.can_create_project?(user))
     |> assign(:form, nil)
     |> assign(:page_title, "Sprints")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil, editing_sprint: nil)
  end

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
      if sprint.id do
        Sprints.update_sprint(sprint, params)
      else
        Sprints.create_sprint(params)
      end

    case result do
      {:ok, _sprint} ->
        {:noreply,
         socket
         |> put_flash(:info, if(sprint.id, do: "Sprint updated.", else: "Sprint created."))
         |> assign(:sprints, Sprints.list_sprints())
         |> push_patch(to: ~p"/sprints")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "sprint"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    sprint = Sprints.get_sprint!(id)

    case Sprints.delete_sprint(sprint) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sprint deleted.")
         |> assign(:sprints, Sprints.list_sprints())}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Cannot delete sprint — it has features assigned to it.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp build_form(sprint), do: Sprints.change_sprint(sprint) |> to_form(as: "sprint")

  defp sprint_status(%Sprint{start_date: nil}), do: :upcoming
  defp sprint_status(%Sprint{end_date: nil}), do: :upcoming

  defp sprint_status(sprint) do
    today = Date.utc_today()

    cond do
      Date.compare(today, sprint.start_date) == :lt -> :upcoming
      Date.compare(today, sprint.end_date) == :gt -> :past
      true -> :current
    end
  end

  defp status_label(:current), do: {"Current", "bg-emerald-100 text-emerald-700"}
  defp status_label(:upcoming), do: {"Upcoming", "bg-blue-100 text-blue-700"}
  defp status_label(:past), do: {"Past", "bg-zinc-100 text-zinc-500"}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Page header --%>
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-semibold text-zinc-900">Sprints</h1>
        <.link
          :if={@can_manage}
          patch={~p"/sprints/new"}
          class="rounded bg-zinc-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-zinc-700"
        >
          New Sprint
        </.link>
      </div>

      <%!-- Sprint table --%>
      <div class="overflow-hidden rounded-lg border border-zinc-200">
        <table class="min-w-full divide-y divide-zinc-200 text-sm">
          <thead class="bg-zinc-50">
            <tr>
              <th class="px-4 py-3 text-left font-medium text-zinc-500">#</th>
              <th class="px-4 py-3 text-left font-medium text-zinc-500">Name</th>
              <th class="px-4 py-3 text-left font-medium text-zinc-500">Start</th>
              <th class="px-4 py-3 text-left font-medium text-zinc-500">End</th>
              <th class="px-4 py-3 text-left font-medium text-zinc-500">Status</th>
              <th :if={@can_manage} class="px-4 py-3" />
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-100 bg-white">
            <tr :if={@sprints == []}>
              <td colspan="6" class="px-4 py-8 text-center text-zinc-400">No sprints yet.</td>
            </tr>
            <tr :for={sprint <- @sprints} class="hover:bg-zinc-50">
              <td class="px-4 py-3 font-medium text-zinc-900">{sprint.number}</td>
              <td class="px-4 py-3 text-zinc-700">{sprint.name || "—"}</td>
              <td class="px-4 py-3 text-zinc-600">{sprint.start_date}</td>
              <td class="px-4 py-3 text-zinc-600">{sprint.end_date}</td>
              <td class="px-4 py-3">
                <% {label, classes} = status_label(sprint_status(sprint)) %>
                <span class={"inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{classes}"}>
                  {label}
                </span>
              </td>
              <td :if={@can_manage} class="px-4 py-3 text-right">
                <div class="flex justify-end gap-3">
                  <.link
                    patch={~p"/sprints/#{sprint.id}/edit"}
                    class="text-zinc-500 hover:text-zinc-900"
                  >
                    Edit
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={sprint.id}
                    data-confirm={"Delete Sprint #{sprint.number}? This cannot be undone."}
                    class="text-red-500 hover:text-red-700"
                  >
                    Delete
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
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
