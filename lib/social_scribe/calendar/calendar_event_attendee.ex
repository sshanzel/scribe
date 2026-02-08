defmodule SocialScribe.Calendar.CalendarEventAttendee do
  @moduledoc """
  Schema for calendar event attendees.

  This is a join table between calendar_events and contacts that stores
  per-event attendee information like display name and response status.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Calendar.CalendarEvent
  alias SocialScribe.Contacts.Contact

  @type t :: %__MODULE__{}

  schema "calendar_event_attendees" do
    field :display_name, :string
    field :response_status, :string
    field :is_organizer, :boolean, default: false

    belongs_to :calendar_event, CalendarEvent
    belongs_to :contact, Contact

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(attendee, attrs) do
    attendee
    |> cast(attrs, [:calendar_event_id, :contact_id, :display_name, :response_status, :is_organizer])
    |> validate_required([:calendar_event_id, :contact_id])
    |> foreign_key_constraint(:calendar_event_id)
    |> foreign_key_constraint(:contact_id)
    |> unique_constraint([:calendar_event_id, :contact_id],
      name: :calendar_event_attendees_calendar_event_id_contact_id_index,
      message: "attendee already exists for this event"
    )
  end

  @doc """
  Returns the display name for the attendee.
  Falls back to contact name, then email.
  """
  def display_name(%__MODULE__{display_name: name, contact: %Contact{} = contact}) do
    cond do
      name && name != "" -> name
      contact.name && contact.name != "" -> contact.name
      true -> contact.email
    end
  end

  def display_name(%__MODULE__{display_name: name}) when is_binary(name) and name != "" do
    name
  end

  def display_name(_), do: nil
end
