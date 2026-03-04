defmodule Agency.Repo.Migrations.RenameDailyRateToHourlyRate do
  use Ecto.Migration

  def change do
    rename table(:users), :daily_rate, to: :hourly_rate
  end
end
