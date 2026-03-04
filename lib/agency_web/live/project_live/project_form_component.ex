defmodule AgencyWeb.ProjectLive.ProjectFormComponent do
  use AgencyWeb, :live_component

  alias Agency.Planning

  @impl true
  def update(%{project: project} = assigns, socket) do
    project = project || %Agency.Planning.Project{}
    changeset = Planning.change_project(project)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:project, project)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      socket.assigns.project
      |> Planning.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"project" => params}, socket) do
    save_project(socket, socket.assigns.project, params)
  end

  defp save_project(socket, %{id: nil}, params) do
    params = Map.put(params, "owner_id", socket.assigns.current_user.id)

    case Planning.create_project(params) do
      {:ok, project} ->
        send(self(), {:project_saved, project})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_project(socket, project, params) do
    case Planning.update_project(project, params) do
      {:ok, updated} ->
        send(self(), {:project_saved, updated})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "project"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {if @project.id, do: "Edit Project", else: "New Project"}
      </.header>

      <.simple_form
        for={@form}
        id={"project-form-#{@id}"}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Project name" required />
        <.input field={@form[:description]} type="textarea" label="Description" rows="3" />
        <.input
          field={@form[:objective]}
          type="textarea"
          label="Objective / Bet"
          rows="3"
          phx-debounce="blur"
        />
        <.input
          field={@form[:status]}
          type="select"
          label="Status"
          options={[
            {"Draft", :draft},
            {"Active", :active},
            {"On Hold", :on_hold},
            {"Completed", :completed},
            {"Archived", :archived}
          ]}
        />
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:start_date]} type="date" label="Start date" />
          <.input field={@form[:end_date]} type="date" label="End date" />
        </div>
        <.input
          field={@form[:owner_id]}
          type="select"
          label="Owner"
          options={Enum.map(@all_users, &{&1.name, &1.id})}
          prompt="Select owner"
        />
        <:actions>
          <.button phx-disable-with="Saving...">
            {if @project.id, do: "Update project", else: "Create project"}
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
