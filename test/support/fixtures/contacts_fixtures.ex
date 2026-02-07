defmodule SocialScribe.ContactsFixtures do
  @moduledoc """
  Fixtures for creating contacts in tests.

  Contacts are now global (one per email) and linked to users through
  calendar_event_attendees. Use `contact_with_event_fixture/1` to create
  a contact that appears in a user's calendar events.
  """

  alias SocialScribe.Contacts
  alias SocialScribe.CalendarFixtures
  alias SocialScribe.AccountsFixtures

  @doc """
  Creates a standalone contact (not linked to any calendar event).
  """
  def contact_fixture(attrs \\ %{}) do
    {:ok, contact} =
      Contacts.create_contact(%{
        name: attrs[:name] || "John Doe",
        email: attrs[:email] || "contact#{System.unique_integer([:positive])}@example.com"
      })

    contact
  end

  @doc """
  Creates a contact and links it to a calendar event for the given user.
  This makes the contact visible in the user's contact search.
  """
  def contact_with_event_fixture(attrs \\ %{}) do
    user = attrs[:user] || AccountsFixtures.user_fixture()

    # Create a calendar event for this user
    calendar_event =
      attrs[:calendar_event] ||
        CalendarFixtures.calendar_event_fixture(%{user_id: user.id})

    # Create the contact
    contact_name = attrs[:name] || "John Doe"
    contact_email = attrs[:email] || "contact#{System.unique_integer([:positive])}@example.com"

    {:ok, contact} = Contacts.find_or_create_contact(%{name: contact_name, email: contact_email})

    # Link contact to calendar event
    {:ok, _attendee} =
      Contacts.create_calendar_event_attendee(%{
        calendar_event_id: calendar_event.id,
        contact_id: contact.id,
        display_name: contact_name,
        response_status: "accepted",
        is_organizer: false
      })

    %{contact: contact, calendar_event: calendar_event, user: user}
  end
end
