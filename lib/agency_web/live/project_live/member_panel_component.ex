defmodule AgencyWeb.ProjectLive.MemberPanelComponent do
  use AgencyWeb, :live_component

  alias Agency.Planning

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("add_member", %{"user_id" => user_id, "role" => role}, socket)
      when user_id != "" do
    attrs = %{
      project_id: socket.assigns.project.id,
      user_id: user_id,
      role: role
    }

    case Planning.add_project_member(attrs) do
      {:ok, _} ->
        send(self(), {:member_changed, :added})
        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add member. They may already be on the project.")}
    end
  end

  def handle_event("add_member", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_member", %{"id" => pm_id}, socket) do
    pm = Planning.get_project_member!(pm_id)
    Planning.remove_project_member(pm)
    send(self(), {:member_changed, :removed})
    {:noreply, socket}
  end

  def handle_event("update_member_role", %{"id" => pm_id, "role" => role}, socket) do
    pm = Planning.get_project_member!(pm_id)

    case Planning.update_project_member(pm, %{role: role}) do
      {:ok, _} ->
        send(self(), {:member_changed, :updated})
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update role.")}
    end
  end

  defp non_members(all_users, project) do
    member_ids = Enum.map(project.project_members, & &1.user_id)
    Enum.reject(all_users, &(&1.id in member_ids))
  end

  defp role_color(:owner), do: "bg-zinc-800 text-white"
  defp role_color(:contributor), do: "bg-blue-100 text-blue-700"
  defp role_color(:stakeholder), do: "bg-amber-100 text-amber-700"
  defp role_color(_), do: "bg-zinc-100 text-zinc-600"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-lg border border-zinc-200 bg-white p-4">
      <h2 class="text-sm font-semibold text-zinc-700 mb-3">Project members</h2>

      <%!-- Member list --%>
      <div :if={@project.project_members != []} class="divide-y divide-zinc-100 mb-4">
        <div :for={pm <- @project.project_members} class="flex items-center justify-between py-2">
          <div class="flex items-center gap-3">
            <span class="text-sm font-medium text-zinc-800">{pm.user.name}</span>
            <span class="text-xs text-zinc-400">{Phoenix.Naming.humanize(pm.user.discipline)}</span>
          </div>
          <div class="flex items-center gap-2">
            <select
              :if={@can_assign}
              phx-change="update_member_role"
              phx-value-id={pm.id}
              phx-target={@myself}
              name="role"
              class="text-xs rounded border-zinc-300 py-0.5"
            >
              <option value="owner" selected={pm.role == :owner}>Owner</option>
              <option value="contributor" selected={pm.role == :contributor}>Contributor</option>
              <option value="stakeholder" selected={pm.role == :stakeholder}>Stakeholder</option>
            </select>
            <span
              :if={!@can_assign}
              class={["inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium", role_color(pm.role)]}
            >
              {Phoenix.Naming.humanize(pm.role)}
            </span>
            <button
              :if={@can_assign}
              phx-click="remove_member"
              phx-value-id={pm.id}
              phx-target={@myself}
              class="text-zinc-300 hover:text-red-500 text-lg leading-none"
              aria-label="Remove"
            >
              ×
            </button>
          </div>
        </div>
      </div>

      <p :if={@project.project_members == []} class="text-xs text-zinc-400 mb-4">
        No members yet.
      </p>

      <%!-- Add member form --%>
      <form
        :if={@can_assign}
        phx-submit="add_member"
        phx-target={@myself}
        class="flex items-end gap-2"
      >
        <div class="flex-1">
          <label class="block text-xs font-medium text-zinc-600 mb-1">Add member</label>
          <select name="user_id" class="w-full text-sm rounded border-zinc-300 py-1.5">
            <option value="">Select a person…</option>
            <option :for={u <- non_members(@all_users, @project)} value={u.id}>
              {u.name} — {Phoenix.Naming.humanize(u.discipline)}
            </option>
          </select>
        </div>
        <div>
          <label class="block text-xs font-medium text-zinc-600 mb-1">Role</label>
          <select name="role" class="text-sm rounded border-zinc-300 py-1.5">
            <option value="contributor">Contributor</option>
            <option value="owner">Owner</option>
            <option value="stakeholder">Stakeholder</option>
          </select>
        </div>
        <.button type="submit" class="py-1.5">Add</.button>
      </form>
    </div>
    """
  end
end
