defmodule Agency.Authorization do
  @moduledoc """
  Central authorization module. All capability checks live here.

  App roles are stored as a string array on `users.app_roles`.
  An empty array means a regular member — visible to all authenticated users.

  Valid roles:
  - "admin" — full access: user management, all data, all actions
  - "hr"    — can view and edit salary data (hourly_rate)
  - "pm"    — can create projects and assign team members

  Roles are additive: a user with ["pm", "hr"] can do both.
  Admin supersedes all other checks.
  """

  alias Agency.Accounts.User

  # ---------------------------------------------------------------------------
  # Base role check
  # ---------------------------------------------------------------------------

  @doc "Returns true if the user has the given role (atom or string)."
  def has_role?(%User{app_roles: roles}, role) when is_atom(role),
    do: Atom.to_string(role) in (roles || [])

  def has_role?(%User{app_roles: roles}, role) when is_binary(role),
    do: role in (roles || [])

  def has_role?(nil, _role), do: false

  # ---------------------------------------------------------------------------
  # Named capabilities
  # ---------------------------------------------------------------------------

  @doc "Can invite new users or manage existing accounts."
  def can_manage_users?(%User{} = user), do: has_role?(user, :admin)

  @doc "Can view and edit the hourly_rate (salary) of any user."
  def can_view_salary?(%User{} = user),
    do: has_role?(user, :admin) or has_role?(user, :hr)

  @doc "Can create projects and assign team members."
  def can_create_project?(%User{} = user),
    do: has_role?(user, :admin) or has_role?(user, :pm)

  @doc "Can assign members to teams and features."
  def can_assign_members?(%User{} = user),
    do: has_role?(user, :admin) or has_role?(user, :pm)

  @doc "Can view project cost totals (does not imply salary visibility)."
  def can_view_project_cost?(%User{} = user),
    do: has_role?(user, :admin) or has_role?(user, :pm) or has_role?(user, :hr)

  @doc "Can manage app roles for other users."
  def can_manage_roles?(%User{} = user), do: has_role?(user, :admin)
end
