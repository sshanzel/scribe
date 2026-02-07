defmodule SocialScribe.Contacts.Contact do
  @moduledoc """
  Schema for contacts.

  Contacts are shared globally (one record per email) and linked to
  calendar events through the calendar_event_attendees join table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Calendar.CalendarEventAttendee

  schema "contacts" do
    field :name, :string
    field :email, :string

    has_many :calendar_event_attendees, CalendarEventAttendee

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for inserting or updating a contact.
  """
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:name, :email])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> update_change(:email, &String.downcase/1)
    |> unique_constraint(:email,
      name: :contacts_email_index,
      message: "contact with this email already exists"
    )
  end

  @doc """
  Returns the display name for the contact.
  Falls back to email if name is not set.
  """
  def display_name(%__MODULE__{name: name, email: email}) do
    if name && name != "", do: name, else: email
  end
end
