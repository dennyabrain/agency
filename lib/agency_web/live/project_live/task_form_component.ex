defmodule AgencyWeb.ProjectLive.TaskFormComponent do
  use AgencyWeb, :live_component

  alias Agency.Delivery
  alias Agency.Delivery.Task

  @valid_hours [1, 2, 3, 4, 6, 8, 12, 16, 24]

  @impl true
  def update(%{task: task} = assigns, socket) do
    task = task || %Task{}
    changeset = Delivery.change_task(task)
    resources = if task.id, do: Map.get(task, :resources, []), else: []
    task_assignees = if task.id, do: Delivery.list_task_assignees(task.id), else: []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:task, task)
     |> assign(:task_resources, resources)
     |> assign(:task_assignees, task_assignees)
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

  def handle_event("add_assignee", %{"user_id" => user_id, "estimated_hours" => hours}, socket)
      when user_id != "" and hours != "" do
    attrs = %{
      "user_id" => user_id,
      "estimated_hours" => String.to_integer(hours)
    }

    case Delivery.add_task_assignee(socket.assigns.task, attrs) do
      {:ok, _} ->
        task_assignees = Delivery.list_task_assignees(socket.assigns.task.id)
        {:noreply, assign(socket, :task_assignees, task_assignees)}

      {:error, changeset} ->
        msg =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  def handle_event("add_assignee", _params, socket), do: {:noreply, socket}

  def handle_event("remove_assignee", %{"id" => id}, socket) do
    Delivery.remove_task_assignee(id)
    updated = Enum.reject(socket.assigns.task_assignees, &(&1.id == id))
    {:noreply, assign(socket, :task_assignees, updated)}
  end

  def handle_event("add_resource", %{"url" => url} = params, socket) when url != "" do
    attrs = %{
      url: String.trim(url),
      title: params |> Map.get("title", "") |> String.trim() |> nilify(),
      kind: Map.get(params, "kind", "website"),
      task_id: socket.assigns.task.id
    }

    case Delivery.create_resource(attrs) do
      {:ok, resource} ->
        {:noreply, assign(socket, :task_resources, socket.assigns.task_resources ++ [resource])}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add resource. Check the URL.")}
    end
  end

  def handle_event("add_resource", _params, socket), do: {:noreply, socket}

  def handle_event("remove_resource", %{"id" => id}, socket) do
    Delivery.delete_resource(id)
    updated = Enum.reject(socket.assigns.task_resources, &(&1.id == id))
    {:noreply, assign(socket, :task_resources, updated)}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

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

  defp nilify(""), do: nil
  defp nilify(s), do: s

  defp hours_options do
    Enum.map(@valid_hours, fn h ->
      label =
        case h do
          1 -> "1 hour"
          8 -> "8 hours (1 day)"
          16 -> "16 hours (2 days)"
          24 -> "24 hours (3 days)"
          n -> "#{n} hours"
        end

      {label, h}
    end)
  end

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

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {if @task.id, do: "Edit Task", else: "New Task"}
      </.header>

      <%!-- Core task fields --%>
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
          <.input field={@form[:due_date]} type="date" label="Due date" />
        </div>

        <:actions>
          <.button phx-disable-with="Saving...">
            {if @task.id, do: "Update task", else: "Create task"}
          </.button>
        </:actions>
      </.simple_form>

      <%!-- Hint for new tasks --%>
      <p :if={!@task.id} class="mt-2 text-xs text-zinc-400">
        Assignees can be added after creating the task.
      </p>

      <%!-- Assignees — only shown when editing an existing task --%>
      <div :if={@task.id} class="mt-6 space-y-2">
        <p class="text-sm font-semibold leading-6 text-zinc-800">Assignees</p>

        <div :if={@task_assignees != []} class="divide-y divide-zinc-100 rounded-lg border border-zinc-200">
          <div
            :for={ta <- @task_assignees}
            class="flex items-center justify-between px-3 py-2 text-sm"
          >
            <span class="text-zinc-800">{if ta.assignee, do: ta.assignee.name, else: "Unknown"}</span>
            <div class="flex items-center gap-3">
              <span class="text-zinc-500">{ta.estimated_hours}h</span>
              <button
                phx-click="remove_assignee"
                phx-value-id={ta.id}
                phx-target={@myself}
                type="button"
                class="text-zinc-300 hover:text-red-500 leading-none"
                aria-label="Remove"
              >
                ×
              </button>
            </div>
          </div>
        </div>

        <form
          phx-submit="add_assignee"
          phx-target={@myself}
          id={"task-assignee-form-#{@task.id}"}
          class="flex items-center gap-2 flex-wrap"
        >
          <select
            name="user_id"
            class="flex-1 min-w-40 text-sm rounded border-zinc-300 py-1"
            required
          >
            <option value="">Select person…</option>
            <%= for user <- @all_users do %>
              <option value={user.id}>{user.name}</option>
            <% end %>
          </select>
          <select name="estimated_hours" class="text-sm rounded border-zinc-300 py-1" required>
            <option value="">Hours…</option>
            <%= for {label, value} <- hours_options() do %>
              <option value={value}>{label}</option>
            <% end %>
          </select>
          <button
            type="submit"
            class="rounded-lg bg-zinc-100 px-3 py-1 text-xs font-semibold text-zinc-700 hover:bg-zinc-200"
          >
            Add
          </button>
        </form>
      </div>

      <%!-- Resources — only shown when editing an existing task --%>
      <div :if={@task.id} class="mt-6 space-y-2">
        <p class="text-sm font-semibold leading-6 text-zinc-800">Resources</p>

        <div :if={@task_resources != []} class="flex flex-wrap gap-2 mb-2">
          <div
            :for={r <- @task_resources}
            class="flex items-center gap-1.5 rounded-full bg-zinc-50 border border-zinc-200 pl-2 pr-1 py-1 text-xs"
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
              phx-click="remove_resource"
              phx-value-id={r.id}
              phx-target={@myself}
              type="button"
              class="text-zinc-300 hover:text-red-500 leading-none ml-0.5"
              aria-label="Remove"
            >
              ×
            </button>
          </div>
        </div>

        <form
          phx-submit="add_resource"
          phx-target={@myself}
          id={"task-resource-form-#{@task.id}"}
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
            class="w-32 text-sm rounded border-zinc-300 py-1 px-2"
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
          <button
            type="submit"
            class="rounded-lg bg-zinc-100 px-3 py-1 text-xs font-semibold text-zinc-700 hover:bg-zinc-200"
          >
            Add
          </button>
        </form>
      </div>
    </div>
    """
  end
end
