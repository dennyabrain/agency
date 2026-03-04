defmodule AgencyWeb.Router do
  use AgencyWeb, :router

  import AgencyWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgencyWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # ---------------------------------------------------------------------------
  # Authenticated app routes — require login
  # ---------------------------------------------------------------------------
  scope "/", AgencyWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :app,
      on_mount: [{AgencyWeb.UserAuth, :ensure_authenticated}] do
      live "/", DashboardLive, :index
      live "/workload", WorkloadLive, :index
      live "/weekly-notes", WeeklyNotesLive, :index
      live "/sprints", SprintsLive, :index
      live "/sprints/new", SprintsLive, :new
      live "/sprints/:id/edit", SprintsLive, :edit
      live "/projects/:id/plan", ProjectLive, :plan
      live "/projects/:id/track", ProjectLive, :track
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end

    live_session :admin,
      on_mount: [{AgencyWeb.UserAuth, :ensure_admin}] do
      live "/admin/users", Admin.UsersLive, :index
    end
  end

  # ---------------------------------------------------------------------------
  # Guest-only routes — redirect logged-in users away
  # ---------------------------------------------------------------------------
  scope "/", AgencyWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{AgencyWeb.UserAuth, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  # ---------------------------------------------------------------------------
  # Routes accessible to all (authenticated or not)
  # ---------------------------------------------------------------------------
  scope "/", AgencyWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{AgencyWeb.UserAuth, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  # ---------------------------------------------------------------------------
  # Dev tooling
  # ---------------------------------------------------------------------------
  if Application.compile_env(:agency, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AgencyWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
