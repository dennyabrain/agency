defmodule AgencyWeb.Admin.UsersLive do
  use AgencyWeb, :live_view

  alias Agency.Accounts

  @roles ~w(admin hr pm)

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Users — Admin")
      |> assign(:users, Accounts.list_users())
      |> assign(:roles, @roles)
      |> assign(:editing_user, nil)
      |> assign(:form, nil)
      |> assign(:creating?, false)
      |> assign(:create_form, to_form(Accounts.change_user_new()))

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # New user
  # ---------------------------------------------------------------------------

  def handle_event("new", _params, socket) do
    socket =
      socket
      |> assign(:creating?, true)
      |> assign(:create_form, to_form(Accounts.change_user_new()))
      |> assign(:editing_user, nil)
      |> assign(:form, nil)

    {:noreply, socket}
  end

  def handle_event("cancel_create", _params, socket) do
    {:noreply, assign(socket, creating?: false)}
  end

  def handle_event("validate_new", %{"user" => params}, socket) do
    params = coerce_roles(params)

    create_form =
      Accounts.change_user_new(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :create_form, create_form)}
  end

  def handle_event("create", %{"user" => params}, socket) do
    params = coerce_roles(params)

    case Accounts.admin_create_user(params) do
      {:ok, _user} ->
        socket =
          socket
          |> put_flash(:info, "User created.")
          |> assign(:users, Accounts.list_users())
          |> assign(:creating?, false)

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :create_form, to_form(changeset))}
    end
  end

  # ---------------------------------------------------------------------------
  # Edit user
  # ---------------------------------------------------------------------------

  def handle_event("edit", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    socket =
      socket
      |> assign(:editing_user, user)
      |> assign(:form, to_form(Accounts.change_user_admin(user)))
      |> assign(:creating?, false)

    {:noreply, socket}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, editing_user: nil, form: nil)}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    params = coerce_roles(params)

    form =
      socket.assigns.editing_user
      |> Accounts.change_user_admin(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"user" => params}, socket) do
    params = coerce_roles(params)

    case Accounts.admin_update_user(socket.assigns.editing_user, params) do
      {:ok, _user} ->
        socket =
          socket
          |> put_flash(:info, "User updated.")
          |> assign(:users, Accounts.list_users())
          |> assign(:editing_user, nil)
          |> assign(:form, nil)

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # ---------------------------------------------------------------------------
  # Delete user
  # ---------------------------------------------------------------------------

  def handle_event("delete", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    case Accounts.delete_user(user) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "#{user.name} was deleted.")
          |> assign(:users, Accounts.list_users())
          |> assign(:editing_user, nil)
          |> assign(:form, nil)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not delete #{user.name}.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Role checkboxes submit as %{"admin" => "true"} map or are absent entirely.
  # Normalise to a plain list of selected role strings before casting.
  defp coerce_roles(%{"app_roles" => roles} = params) when is_map(roles) do
    selected = for {role, "true"} <- roles, do: role
    Map.put(params, "app_roles", selected)
  end

  defp coerce_roles(params), do: Map.put(params, "app_roles", [])

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  defp employment_badge(%{type: :contractor} = assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-medium text-amber-700">
      Contractor
    </span>
    """
  end

  defp employment_badge(assigns) do
    ~H"""
    <span class="inline-flex items-center rounded-full bg-blue-100 px-2 py-0.5 text-xs font-medium text-blue-700">
      Employee
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Users
        <:subtitle>Manage team members, roles, and billing rates.</:subtitle>
        <:actions>
          <.button phx-click="new">New User</.button>
        </:actions>
      </.header>

      <.table id="admin-users" rows={@users}>
        <:col :let={u} label="Name">{u.name}</:col>
        <:col :let={u} label="Email">{u.email}</:col>
        <:col :let={u} label="Type"><.employment_badge type={u.employment_type} /></:col>
        <:col :let={u} label="Title">{u.title || "—"}</:col>
        <:col :let={u} label="Discipline">{Phoenix.Naming.humanize(u.discipline)}</:col>
        <:col :let={u} label="Seniority">{Phoenix.Naming.humanize(u.seniority)}</:col>
        <:col :let={u} label="Rate">
          {if u.hourly_rate, do: "$#{Decimal.round(u.hourly_rate, 0)}/hr", else: "—"}
        </:col>
        <:col :let={u} label="Roles">
          <span :if={u.app_roles == []} class="text-zinc-400">none</span>
          <span
            :for={role <- u.app_roles}
            class="mr-1 inline-flex items-center rounded-full bg-zinc-100 px-2 py-0.5 text-xs font-medium text-zinc-700"
          >
            {role}
          </span>
        </:col>
        <:action :let={u}>
          <button phx-click="edit" phx-value-id={u.id} class="text-sm font-medium">
            Edit
          </button>
        </:action>
      </.table>

      <%!-- Edit modal --%>
      <.modal :if={@editing_user} id="edit-user-modal" show={true} on_cancel={JS.push("cancel")}>
        <.header>
          Edit {@editing_user.name}
        </.header>

        <.form for={@form} phx-change="validate" phx-submit="save" class="mt-6 space-y-4">
          <.input field={@form[:name]} label="Name" required />
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:title]} label="Title" />

          <.input
            field={@form[:discipline]}
            type="select"
            label="Discipline"
            options={[
              {"Design", :design},
              {"Engineering", :engineering},
              {"Research", :research},
              {"QA", :qa},
              {"Data", :data},
              {"Management", :management}
            ]}
            required
          />

          <.input
            field={@form[:seniority]}
            type="select"
            label="Seniority"
            options={[
              {"Junior", :junior},
              {"Mid", :mid},
              {"Senior", :senior},
              {"Lead", :lead},
              {"Principal", :principal}
            ]}
            required
          />

          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:hourly_rate]}
              type="number"
              label="Hourly rate ($)"
              step="0.01"
              min="0"
            />
            <.input
              field={@form[:employment_type]}
              type="select"
              label="Employment type"
              options={[{"Employee", :employee}, {"Contractor", :contractor}]}
              required
            />
          </div>

          <fieldset>
            <legend class="block text-sm font-semibold leading-6 text-zinc-800">Roles</legend>
            <div class="mt-2 flex gap-6">
              <label
                :for={role <- @roles}
                class="flex cursor-pointer items-center gap-2 text-sm text-zinc-700"
              >
                <input
                  type="checkbox"
                  name={"user[app_roles][#{role}]"}
                  value="true"
                  checked={role in (@form[:app_roles].value || [])}
                  class="rounded border-zinc-300"
                />
                {String.upcase(role)}
              </label>
            </div>
          </fieldset>

          <div class="mt-6 flex items-center justify-between">
            <button
              type="button"
              phx-click="delete"
              phx-value-id={@editing_user.id}
              data-confirm={"Delete #{@editing_user.name}? This cannot be undone."}
              class="text-sm font-medium text-red-600 hover:text-red-500"
            >
              Delete user
            </button>

            <div class="flex gap-3">
              <.button type="button" phx-click="cancel">Cancel</.button>
              <.button type="submit">Save changes</.button>
            </div>
          </div>
        </.form>
      </.modal>

      <%!-- Create modal --%>
      <.modal
        :if={@creating?}
        id="create-user-modal"
        show={true}
        on_cancel={JS.push("cancel_create")}
      >
        <.header>
          New User
        </.header>

        <.form
          for={@create_form}
          phx-change="validate_new"
          phx-submit="create"
          class="mt-6 space-y-4"
        >
          <.input field={@create_form[:name]} label="Name" required />
          <.input field={@create_form[:email]} type="email" label="Email" required />
          <.input field={@create_form[:title]} label="Title" />

          <.input
            field={@create_form[:discipline]}
            type="select"
            label="Discipline"
            options={[
              {"Design", :design},
              {"Engineering", :engineering},
              {"Research", :research},
              {"QA", :qa},
              {"Data", :data},
              {"Management", :management}
            ]}
            required
          />

          <.input
            field={@create_form[:seniority]}
            type="select"
            label="Seniority"
            options={[
              {"Junior", :junior},
              {"Mid", :mid},
              {"Senior", :senior},
              {"Lead", :lead},
              {"Principal", :principal}
            ]}
            required
          />

          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@create_form[:hourly_rate]}
              type="number"
              label="Hourly rate ($)"
              step="0.01"
              min="0"
            />
            <.input
              field={@create_form[:employment_type]}
              type="select"
              label="Employment type"
              options={[{"Employee", :employee}, {"Contractor", :contractor}]}
              required
            />
          </div>

          <.input field={@create_form[:password]} type="password" label="Password" required />

          <fieldset>
            <legend class="block text-sm font-semibold leading-6 text-zinc-800">Roles</legend>
            <div class="mt-2 flex gap-6">
              <label
                :for={role <- @roles}
                class="flex cursor-pointer items-center gap-2 text-sm text-zinc-700"
              >
                <input
                  type="checkbox"
                  name={"user[app_roles][#{role}]"}
                  value="true"
                  checked={role in (@create_form[:app_roles].value || [])}
                  class="rounded border-zinc-300"
                />
                {String.upcase(role)}
              </label>
            </div>
          </fieldset>

          <div class="mt-6 flex justify-end gap-3">
            <.button type="button" phx-click="cancel_create">Cancel</.button>
            <.button type="submit">Create user</.button>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end
end
