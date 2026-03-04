defmodule AgencyWeb.ProjectLive.TaskFormComponent do
  use AgencyWeb, :live_component

  alias Agency.Delivery
  alias Agency.Delivery.Task

  @impl true
  def update(%{task: task} = assigns, socket) do
    task = task || %Task{}
    changeset = Delivery.change_task(task)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:task, task)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"task" => params}, socket) do
    changeset =
      socket.assigns.task
      |> Delivery.change_task(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"task" => params}, socket) do
    save_task(socket, socket.assigns.task, params)
  end

  defp save_task(socket, %{id: nil}, params) do
    params = Map.put(params, "feature_id", socket.assigns.feature_id)

    case Delivery.create_task(params) do
      {:ok, task} ->
        send(self(), {:task_saved, task})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_task(socket, task, params) do
    case Delivery.update_task(task, params) do
      {:ok, updated} ->
        send(self(), {:task_saved, updated})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "task"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {if @task.id, do: "Edit Task", else: "New Task"}
      </.header>

      <.simple_form
        for={@form}
        id={"task-form-#{@id}"}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Task name" required />
        <.input field={@form[:description]} type="textarea" label="Description" rows="2" />
        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:status]}
            type="select"
            label="Status"
            options={[
              {"To do", :todo},
              {"In progress", :in_progress},
              {"In review", :in_review},
              {"Done", :done},
              {"Blocked", :blocked}
            ]}
          />
          <.input
            field={@form[:estimated_hours]}
            type="select"
            label="Estimated duration"
            options={[
              {"1 hour", 1},
              {"2 hours", 2},
              {"3 hours", 3},
              {"4 hours", 4},
              {"6 hours", 6},
              {"8 hours (1 day)", 8},
              {"12 hours", 12},
              {"16 hours (2 days)", 16},
              {"24 hours (3 days)", 24}
            ]}
            prompt="Select duration"
          />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:due_date]} type="date" label="Due date" />
          <.input
            field={@form[:assignee_id]}
            type="select"
            label="Assignee"
            options={Enum.map(@all_users, &{&1.name, &1.id})}
            prompt="Unassigned"
          />
        </div>
        <:actions>
          <.button phx-disable-with="Saving...">
            {if @task.id, do: "Update task", else: "Create task"}
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
