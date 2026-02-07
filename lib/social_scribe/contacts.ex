defmodule SocialScribe.Contacts do
  @moduledoc """
  The Contacts context for managing contacts.

  Contacts are shared globally (one record per email) and are linked to users
  through their calendar events. A user can only see contacts that appear in
  their calendar events.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias SocialScribe.Contacts.Contact
  alias SocialScribe.Calendar.CalendarEvent
  alias SocialScribe.Calendar.CalendarEventAttendee
  alias SocialScribe.Accounts.User

  @doc """
  Creates a new contact.

  Returns `{:error, changeset}` if the email already exists.
  Use `find_or_create_contact/1` to get existing contact instead.
  """
  def create_contact(attrs) do
    %Contact{}
    |> Contact.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing contact.
  """
  def update_contact(%Contact{} = contact, attrs) do
    contact
    |> Contact.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a contact.
  """
  def delete_contact(%Contact{} = contact) do
    Repo.delete(contact)
  end

  @doc """
  Gets a contact by ID.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_contact!(id), do: Repo.get!(Contact, id)

  @doc """
  Gets a contact by ID, returns nil if not found.
  """
  def get_contact(id), do: Repo.get(Contact, id)

  @doc """
  Gets a contact by email.

  Returns nil if not found.
  """
  def get_contact_by_email(email) when is_binary(email) do
    email = String.downcase(email)

    Contact
    |> where([c], c.email == ^email)
    |> Repo.one()
  end

  def get_contact_by_email(_), do: nil

  @doc """
  Lists all contacts visible to a user.

  A user can only see contacts that appear in their calendar events.
  """
  def list_contacts(%User{id: user_id}), do: list_contacts(user_id)

  def list_contacts(user_id) when is_integer(user_id) do
    from(c in Contact,
      join: cea in CalendarEventAttendee, on: cea.contact_id == c.id,
      join: ce in CalendarEvent, on: ce.id == cea.calendar_event_id,
      where: ce.user_id == ^user_id,
      distinct: true,
      order_by: [asc: c.name]
    )
    |> Repo.all()
  end

  @doc """
  Searches contacts by name or email for autocomplete.

  Returns contacts matching the query string (case-insensitive) that appear
  in the user's calendar events.
  """
  def search_contacts(%User{id: user_id}, query), do: search_contacts(user_id, query)

  def search_contacts(user_id, query) when is_integer(user_id) and is_binary(query) do
    search_term = "%#{query}%"

    from(c in Contact,
      join: cea in CalendarEventAttendee, on: cea.contact_id == c.id,
      join: ce in CalendarEvent, on: ce.id == cea.calendar_event_id,
      where: ce.user_id == ^user_id,
      where: ilike(c.name, ^search_term) or ilike(c.email, ^search_term),
      distinct: true,
      order_by: [asc: c.name],
      limit: 10
    )
    |> Repo.all()
  end

  def search_contacts(_user_id, _query), do: []

  @doc """
  Finds or creates a contact by email.

  If a contact with the email exists, returns it (optionally updating the name).
  Otherwise, creates a new contact with the given attributes.
  """
  def find_or_create_contact(%{email: email} = attrs) when is_binary(email) do
    email = String.downcase(email)

    case get_contact_by_email(email) do
      nil ->
        create_contact(attrs)

      %Contact{} = contact ->
        # Optionally update name if provided and current name is empty
        if attrs[:name] && (is_nil(contact.name) || contact.name == "") do
          update_contact(contact, %{name: attrs[:name]})
        else
          {:ok, contact}
        end
    end
  end

  def find_or_create_contact(%{"email" => email} = attrs) when is_binary(email) do
    find_or_create_contact(%{
      email: email,
      name: Map.get(attrs, "name")
    })
  end

  def find_or_create_contact(_), do: {:error, :invalid_attrs}

  @doc """
  Creates a calendar event attendee record linking a contact to an event.

  If the attendee already exists for this event, returns the existing record.
  """
  def create_calendar_event_attendee(attrs) do
    changeset = CalendarEventAttendee.changeset(%CalendarEventAttendee{}, attrs)

    case Repo.insert(changeset, on_conflict: :nothing) do
      {:ok, %CalendarEventAttendee{id: nil}} ->
        # Conflict occurred, fetch the existing record
        calendar_event_id = attrs[:calendar_event_id] || attrs["calendar_event_id"]
        contact_id = attrs[:contact_id] || attrs["contact_id"]

        existing =
          CalendarEventAttendee
          |> where([a], a.calendar_event_id == ^calendar_event_id and a.contact_id == ^contact_id)
          |> Repo.one()

        {:ok, existing}

      result ->
        result
    end
  end

  @doc """
  Syncs attendees for a calendar event by deleting existing and creating fresh.

  This ensures removed attendees are cleaned up when an event is resynced.
  """
  def sync_attendees_from_event_data(calendar_event_id, attendees) when is_list(attendees) do
    # Delete existing attendees for this event
    from(a in CalendarEventAttendee, where: a.calendar_event_id == ^calendar_event_id)
    |> Repo.delete_all()

    # Create fresh attendee records
    create_attendees_from_event_data(calendar_event_id, attendees)
  end

  def sync_attendees_from_event_data(_calendar_event_id, _attendees), do: []

  @doc """
  Creates contacts and attendee records from calendar event attendees data.

  For each attendee with an email:
  1. Find or create a contact
  2. Create a calendar_event_attendee record linking them

  Returns a list of created attendee records.

  Note: Use `sync_attendees_from_event_data/2` when resyncing events to clean up
  removed attendees.
  """
  def create_attendees_from_event_data(calendar_event_id, attendees) when is_list(attendees) do
    attendees
    |> Enum.filter(fn attendee ->
      email = Map.get(attendee, "email") || Map.get(attendee, :email)
      email != nil && email != ""
    end)
    |> Enum.map(fn attendee ->
      email = Map.get(attendee, "email") || Map.get(attendee, :email)
      display_name = Map.get(attendee, "displayName") || Map.get(attendee, :displayName)
      response_status = Map.get(attendee, "responseStatus") || Map.get(attendee, :responseStatus)
      is_organizer = Map.get(attendee, "organizer") == true || Map.get(attendee, :organizer) == true

      with {:ok, contact} <- find_or_create_contact(%{email: email, name: display_name}),
           {:ok, attendee_record} <-
             create_calendar_event_attendee(%{
               calendar_event_id: calendar_event_id,
               contact_id: contact.id,
               display_name: display_name,
               response_status: response_status,
               is_organizer: is_organizer
             }) do
        attendee_record
      else
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def create_attendees_from_event_data(_calendar_event_id, _attendees), do: []
end
