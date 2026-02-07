defmodule SocialScribe.Repo.Migrations.AddAttendeesToCalendarEvents do
  use Ecto.Migration

  def change do
    alter table(:calendar_events) do
      add :attendees, {:array, :map}, default: []
    end
  end
end
