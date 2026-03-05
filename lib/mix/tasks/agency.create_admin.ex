defmodule Mix.Tasks.Agency.CreateAdmin do
  @shortdoc "Creates a confirmed admin user for initial app setup"

  @moduledoc """
  Creates a confirmed admin user.

      mix agency.create_admin EMAIL NAME DISCIPLINE SENIORITY PASSWORD

  ## Examples

      mix agency.create_admin alice@example.com "Alice Smith" engineering senior "s3cur3p@ssword!"

  ## Disciplines

      design, engineering, research, qa, data, management

  ## Seniority levels

      junior, mid, senior, lead, principal
  """

  use Mix.Task

  @impl Mix.Task
  def run([email, name, discipline, seniority, password]) do
    Mix.Task.run("app.start")

    attrs = %{
      email: email,
      name: name,
      discipline: discipline,
      seniority: seniority,
      password: password
    }

    case Agency.Accounts.create_admin_user(attrs) do
      {:ok, user} ->
        Mix.shell().info("Admin user created: #{user.email} (#{user.name})")

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        Mix.shell().error("Failed to create admin user:")

        Enum.each(errors, fn {field, messages} ->
          Mix.shell().error("  #{field}: #{Enum.join(messages, ", ")}")
        end)

        exit({:shutdown, 1})
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix agency.create_admin EMAIL NAME DISCIPLINE SENIORITY PASSWORD")
    exit({:shutdown, 1})
  end
end
