defmodule SocialScribe.Calendar.CalendarEvent do
  @moduledoc """
  Schema for calendar events synced from Google Calendar.

  Represents a calendar event with its metadata including title, description,
  times, and links. Events are associated with attendees through the
  `CalendarEventAttendee` join table.

  ## Fields

  - `google_event_id` - The unique identifier from Google Calendar
  - `summary` - Event title
  - `description` - Event description
  - `location` - Event location
  - `html_link` - Link to view the event in Google Calendar
  - `hangout_link` - Google Meet link if present
  - `status` - Event status (confirmed, cancelled, etc.)
  - `start_time` - Event start time
  - `end_time` - Event end time
  - `record_meeting` - Whether to record this meeting

  ## Associations

  - `calendar_event_attendees` - Attendees linked to this event
  - `contacts` - Contacts attending this event (through attendees)
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Calendar.CalendarEventAttendee

  @type t :: %__MODULE__{}

  schema "calendar_events" do
    field :status, :string
    field :description, :string
    field :location, :string
    field :google_event_id, :string
    field :summary, :string
    field :html_link, :string
    field :hangout_link, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :record_meeting, :boolean, default: false
    field :user_id, :id
    field :user_credential_id, :id

    has_many :calendar_event_attendees, CalendarEventAttendee
    has_many :contacts, through: [:calendar_event_attendees, :contact]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(calendar_event, attrs) do
    calendar_event
    |> cast(attrs, [
      :google_event_id,
      :summary,
      :description,
      :location,
      :html_link,
      :hangout_link,
      :status,
      :start_time,
      :end_time,
      :record_meeting,
      :user_id,
      :user_credential_id
    ])
    |> validate_required([
      :google_event_id,
      :summary,
      :html_link,
      :status,
      :start_time,
      :end_time,
      :user_id,
      :user_credential_id
    ])
  end
end
