defmodule SocialScribe.Contacts do
  @moduledoc """
  The Contacts context for managing user contacts.

  Contacts are used for tagging in chat messages and matching with CRM data.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias SocialScribe.Contacts.Contact
  alias SocialScribe.Accounts.User

  @doc """
  Creates a new contact for a user.
  """
  def create_contact(%User{} = user, attrs) do
    %Contact{}
    |> Contact.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  def create_contact(user_id, attrs) when is_integer(user_id) do
    %Contact{}
    |> Contact.changeset(Map.put(attrs, :user_id, user_id))
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
  Lists all contacts for a user.
  """
  def list_contacts(%User{id: user_id}), do: list_contacts(user_id)

  def list_contacts(user_id) when is_integer(user_id) do
    Contact
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  @doc """
  Searches contacts by name or email for autocomplete.

  Returns contacts matching the query string (case-insensitive).
  """
  def search_contacts(%User{id: user_id}, query), do: search_contacts(user_id, query)

  def search_contacts(user_id, query) when is_integer(user_id) and is_binary(query) do
    search_term = "%#{query}%"

    Contact
    |> where([c], c.user_id == ^user_id)
    |> where([c], ilike(c.name, ^search_term) or ilike(c.email, ^search_term))
    |> order_by([c], asc: c.name)
    |> limit(10)
    |> Repo.all()
  end

  def search_contacts(_user_id, _query), do: []

  @doc """
  Gets a contact by email for a specific user.

  Returns nil if not found.
  """
  def get_contact_by_email(%User{id: user_id}, email), do: get_contact_by_email(user_id, email)

  def get_contact_by_email(user_id, email) when is_integer(user_id) and is_binary(email) do
    Contact
    |> where([c], c.user_id == ^user_id and c.email == ^email)
    |> Repo.one()
  end

  def get_contact_by_email(_user_id, _email), do: nil

  @doc """
  Finds or creates a contact by email for a user.

  If a contact with the email exists, returns it.
  Otherwise, creates a new contact with the given attributes.
  """
  def find_or_create_contact(%User{} = user, %{email: email} = attrs) when is_binary(email) do
    case get_contact_by_email(user, email) do
      nil -> create_contact(user, attrs)
      contact -> {:ok, contact}
    end
  end

  def find_or_create_contact(%User{} = user, %{"email" => email} = attrs) when is_binary(email) do
    find_or_create_contact(user, %{
      email: email,
      name: Map.get(attrs, "name")
    })
  end

  @doc """
  Creates contacts from calendar event attendees.

  For each attendee with an email, finds or creates a contact.
  Returns a list of contacts.
  """
  def create_contacts_from_attendees(%User{} = user, attendees) when is_list(attendees) do
    attendees
    |> Enum.filter(fn attendee ->
      email = Map.get(attendee, "email") || Map.get(attendee, :email)
      email != nil && email != ""
    end)
    |> Enum.map(fn attendee ->
      email = Map.get(attendee, "email") || Map.get(attendee, :email)
      name = Map.get(attendee, "name") || Map.get(attendee, :name)

      case find_or_create_contact(user, %{email: email, name: name}) do
        {:ok, contact} -> contact
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def create_contacts_from_attendees(_user, _attendees), do: []
end
