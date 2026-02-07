defmodule SocialScribe.Repo.Migrations.AddNotNullToIsOrganizer do
  use Ecto.Migration

  def change do
    alter table(:calendar_event_attendees) do
      modify :is_organizer, :boolean, null: false, default: false
    end
  end
end
