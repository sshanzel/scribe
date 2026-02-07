defmodule SocialScribe.Repo.Migrations.CreateCalendarEventAttendees do
  use Ecto.Migration

  def change do
    create table(:calendar_event_attendees) do
      add :calendar_event_id, references(:calendar_events, on_delete: :delete_all), null: false
      add :contact_id, references(:contacts, on_delete: :delete_all), null: false
      add :display_name, :string
      add :response_status, :string
      add :is_organizer, :boolean, default: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:calendar_event_attendees, [:calendar_event_id])
    create index(:calendar_event_attendees, [:contact_id])
    create unique_index(:calendar_event_attendees, [:calendar_event_id, :contact_id])
  end
end
