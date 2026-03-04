defmodule AgencyWeb.ProjectLive.FeatureFormComponent do
  use AgencyWeb, :live_component

  alias Agency.Delivery
  alias Agency.Delivery.Feature

  @impl true
  def update(%{feature: feature} = assigns, socket) do
    feature = feature || %Feature{}
    changeset = Delivery.change_feature(feature)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:feature, feature)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"feature" => params}, socket) do
    changeset =
      socket.assigns.feature
      |> Delivery.change_feature(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"feature" => params}, socket) do
    save_feature(socket, socket.assigns.feature, params)
  end

  defp save_feature(socket, %{id: nil}, params) do
    params = Map.put(params, "project_id", socket.assigns.project_id)

    case Delivery.create_feature(params) do
      {:ok, feature} ->
        send(self(), {:feature_saved, feature})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_feature(socket, feature, params) do
    case Delivery.update_feature(feature, params) do
      {:ok, updated} ->
        send(self(), {:feature_saved, updated})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "feature"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {if @feature.id, do: "Edit Feature", else: "New Feature"}
      </.header>

      <.simple_form
        for={@form}
        id={"feature-form-#{@id}"}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} type="text" label="Feature name" required />
        <.input field={@form[:description]} type="textarea" label="Description" rows="2" />
        <.input
          field={@form[:hypothesis]}
          type="textarea"
          label="Hypothesis"
          rows="2"
          phx-debounce="blur"
        />
        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:status]}
            type="select"
            label="Status"
            options={[
              {"Backlog", :backlog},
              {"In progress", :in_progress},
              {"Completed", :completed},
              {"Cancelled", :cancelled}
            ]}
          />
          <.input
            field={@form[:priority]}
            type="number"
            label="Priority"
            min="0"
            phx-debounce="blur"
          />
        </div>
        <.input
          field={@form[:sprint_id]}
          type="select"
          label="Sprint"
          options={sprint_options(@sprints)}
          prompt="No sprint assigned"
        />
        <:actions>
          <.button phx-disable-with="Saving...">
            {if @feature.id, do: "Update feature", else: "Create feature"}
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  defp sprint_options(sprints) do
    Enum.map(sprints, fn s ->
      label =
        if s.name && s.name != "",
          do: "Sprint #{s.number} · #{s.name}",
          else: "Sprint #{s.number}"

      {label, s.id}
    end)
  end
end
