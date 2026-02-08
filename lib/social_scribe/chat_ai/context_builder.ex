defmodule SocialScribe.ChatAI.ContextBuilder do
  @moduledoc """
  Builds context for AI chat by gathering relevant data from meetings and CRM systems.

  This module handles:
  - Gathering CRM data from HubSpot/Salesforce
  - Finding meetings for contacts
  - Building context maps for AI consumption
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias SocialScribe.Accounts.Credentials
  alias SocialScribe.Accounts.User
  alias SocialScribe.Contacts
  alias SocialScribe.Contacts.Contact
  alias SocialScribe.Meetings.Meeting
  alias SocialScribe.Meetings.MeetingParticipant
  alias SocialScribe.Calendar.CalendarEventAttendee

  @max_meetings Application.compile_env(:social_scribe, :chat_max_meetings, 10)
  @max_name_matched_meetings 5

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Gathers context from message metadata.

  Prioritizes contact_id for direct meeting lookup (most efficient),
  falls back to email lookup if contact_id is not available.
  CRM data is included when available for enriched AI context.

  Also finds potential name-matched meetings when email matches are insufficient.
  These are tagged separately so the AI knows they're potential (not confirmed) matches.

  ## Returns
  - `{:ok, context}` where context includes:
    - `:contact` - Contact struct or nil
    - `:crm_data` - CRM data map or nil
    - `:meetings` - Email-matched meetings (confirmed)
    - `:name_matched_meetings` - First name matched meetings (potential)
  """
  # Priority 1: contact_id available (direct lookup, most reliable)
  def gather_context_from_metadata(%User{} = user, %{"contact_id" => contact_id} = metadata)
      when is_integer(contact_id) do
    case Repo.get(Contact, contact_id) do
      %Contact{} = contact ->
        meetings = find_meetings_for_contact(user, contact)
        crm_data = metadata["crm_data"]
        first_name = extract_first_name(metadata["name"])
        name_matched = maybe_find_name_matched_meetings(user, first_name, meetings)

        {:ok,
         %{
           contact: contact,
           crm_data: crm_data,
           meetings: meetings,
           name_matched_meetings: name_matched
         }}

      nil ->
        # Contact was deleted, fall back to email lookup
        gather_context_from_metadata(user, Map.delete(metadata, "contact_id"))
    end
  end

  # Priority 2: email with CRM data
  def gather_context_from_metadata(
        %User{} = user,
        %{"crm_data" => crm_data, "email" => email} = metadata
      )
      when is_map(crm_data) and is_binary(email) and email != "" do
    meetings = find_meetings_by_email(user, email)
    first_name = extract_first_name(metadata["name"])
    name_matched = maybe_find_name_matched_meetings(user, first_name, meetings)

    {:ok,
     %{
       contact: nil,
       crm_data: crm_data,
       meetings: meetings,
       name_matched_meetings: name_matched
     }}
  end

  # Priority 3: CRM data only (no email, rare case)
  def gather_context_from_metadata(%User{} = user, %{"crm_data" => crm_data} = metadata)
      when is_map(crm_data) do
    first_name = extract_first_name(metadata["name"])
    name_matched = find_name_matched_meetings(user, first_name, [])

    {:ok,
     %{
       contact: nil,
       crm_data: crm_data,
       meetings: [],
       name_matched_meetings: name_matched
     }}
  end

  # Priority 4: email only
  def gather_context_from_metadata(%User{} = user, %{"email" => email} = metadata)
      when is_binary(email) and email != "" do
    meetings = find_meetings_by_email(user, email)
    first_name = extract_first_name(metadata["name"])
    name_matched = maybe_find_name_matched_meetings(user, first_name, meetings)

    {:ok,
     %{
       contact: nil,
       crm_data: nil,
       meetings: meetings,
       name_matched_meetings: name_matched
     }}
  end

  # Fallback: no contact info, show recent meetings
  def gather_context_from_metadata(%User{} = user, _metadata) do
    meetings = find_recent_meetings_for_user(user)

    {:ok,
     %{
       contact: nil,
       crm_data: nil,
       meetings: meetings,
       name_matched_meetings: []
     }}
  end

  @doc """
  Gathers context for a user and contact.

  Returns a map with:
  - `:contact` - The contact struct (or nil)
  - `:crm_data` - CRM data from HubSpot/Salesforce (or nil)
  - `:meetings` - List of email-matched meetings (confirmed)
  - `:name_matched_meetings` - List of name-matched meetings (potential)
  """
  def gather_context(%User{} = user, %Contact{} = contact) do
    crm_data = gather_crm_data(user, contact)
    meetings = find_meetings_for_contact(user, contact)
    first_name = extract_first_name(contact.name)
    name_matched = maybe_find_name_matched_meetings(user, first_name, meetings)

    {:ok,
     %{
       contact: contact,
       crm_data: crm_data,
       meetings: meetings,
       name_matched_meetings: name_matched
     }}
  end

  def gather_context(%User{} = user, nil) do
    meetings = find_recent_meetings_for_user(user)

    {:ok,
     %{
       contact: nil,
       crm_data: nil,
       meetings: meetings,
       name_matched_meetings: []
     }}
  end

  # =============================================================================
  # Meeting Queries
  # =============================================================================

  @doc """
  Finds meetings where a contact was an attendee.
  Returns up to #{@max_meetings} most recent meetings.
  """
  def find_meetings_for_contact(user, %Contact{id: contact_id}) do
    Meeting
    |> join(:inner, [m], ce in assoc(m, :calendar_event))
    |> join(:inner, [m, ce], cea in CalendarEventAttendee, on: cea.calendar_event_id == ce.id)
    |> where([m, ce, cea], ce.user_id == ^user.id)
    |> where([m, ce, cea], cea.contact_id == ^contact_id)
    |> order_by([m, ce, cea], desc: m.recorded_at)
    |> limit(@max_meetings)
    |> preload([:meeting_transcript, :meeting_participants, :calendar_event])
    |> Repo.all()
  end

  def find_meetings_for_contact(_user, _contact), do: []

  @doc """
  Finds meetings for a contact by email.

  Looks up the contact in the local contacts table by email, then finds
  meetings where that contact was an attendee.
  """
  def find_meetings_by_email(%User{} = user, email) when is_binary(email) do
    case Contacts.get_contact_by_email(email) do
      nil -> []
      contact -> find_meetings_for_contact(user, contact)
    end
  end

  def find_meetings_by_email(_user, _email), do: []

  @doc """
  Finds the most recent meetings for a user when no specific contact is tagged.
  Returns up to #{@max_meetings} most recent meetings.
  """
  def find_recent_meetings_for_user(%User{id: user_id}) do
    Meeting
    |> join(:inner, [m], ce in assoc(m, :calendar_event))
    |> where([m, ce], ce.user_id == ^user_id)
    |> order_by([m, ce], desc: m.recorded_at)
    |> limit(@max_meetings)
    |> preload([:meeting_transcript, :meeting_participants, :calendar_event])
    |> Repo.all()
  end

  # =============================================================================
  # CRM Data Gathering
  # =============================================================================

  @doc """
  Gathers CRM data for a contact from HubSpot or Salesforce.
  """
  def gather_crm_data(%User{} = user, %Contact{email: email}) when is_binary(email) do
    # Try HubSpot first, then Salesforce
    case get_hubspot_contact_data(user, email) do
      {:ok, data} when is_map(data) ->
        data

      _ ->
        case get_salesforce_contact_data(user, email) do
          {:ok, data} when is_map(data) -> data
          _ -> nil
        end
    end
  end

  defp get_hubspot_contact_data(%User{} = user, email) when is_binary(email) do
    # Use deterministic getter that returns most recently created credential
    case Credentials.get_user_latest_credential(user.id, "hubspot") do
      nil ->
        {:error, :no_hubspot_credential}

      credential ->
        hubspot_api().search_contacts(credential, email)
        |> case do
          {:ok, [contact | _]} when is_map(contact) -> {:ok, contact}
          {:ok, []} -> {:ok, nil}
          {:error, _} = error -> error
        end
    end
  end

  defp get_salesforce_contact_data(%User{} = user, email) when is_binary(email) do
    # Use deterministic getter that returns most recently created credential
    case Credentials.get_user_latest_credential(user.id, "salesforce") do
      nil ->
        {:error, :no_salesforce_credential}

      credential ->
        salesforce_api().search_contacts(credential, email)
        |> case do
          {:ok, [contact | _]} when is_map(contact) -> {:ok, contact}
          {:ok, []} -> {:ok, nil}
          {:error, _} = error -> error
        end
    end
  end

  # =============================================================================
  # Name-Based Meeting Search
  # =============================================================================

  # Only search by name when there are no email-matched meetings
  defp maybe_find_name_matched_meetings(_user, _first_name, [_ | _]), do: []

  defp maybe_find_name_matched_meetings(user, first_name, []) do
    find_name_matched_meetings(user, first_name, [])
  end

  @doc """
  Finds meetings where a participant's first name matches.
  Returns up to #{@max_name_matched_meetings} meetings.

  These are "potential" matches since name matching is less reliable than email.
  """
  def find_name_matched_meetings(_user, nil, _email_meetings), do: []
  def find_name_matched_meetings(_user, "", _email_meetings), do: []

  def find_name_matched_meetings(%User{id: user_id}, first_name, _email_meetings)
      when is_binary(first_name) do
    name_pattern = "#{first_name}%"

    # Subquery to get distinct meeting IDs that match
    matching_ids =
      Meeting
      |> join(:inner, [m], ce in assoc(m, :calendar_event))
      |> join(:inner, [m, ce], mp in MeetingParticipant, on: mp.meeting_id == m.id)
      |> where([m, ce, mp], ce.user_id == ^user_id)
      |> where([m, ce, mp], ilike(mp.name, ^name_pattern))
      |> select([m, ce, mp], m.id)
      |> distinct(true)

    # Query meetings by those IDs, ordered by most recent
    Meeting
    |> where([m], m.id in subquery(matching_ids))
    |> order_by([m], desc: m.recorded_at)
    |> limit(@max_name_matched_meetings)
    |> preload([:meeting_transcript, :meeting_participants, :calendar_event])
    |> Repo.all()
  end

  @doc """
  Extracts the first name from a full name string.
  Returns nil if the name is nil, empty, or whitespace-only.
  """
  def extract_first_name(nil), do: nil
  def extract_first_name(""), do: nil

  def extract_first_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> nil
      trimmed -> trimmed |> String.split(~r/\s+/, parts: 2) |> List.first()
    end
  end

  # =============================================================================
  # API Module Getters (for mocking)
  # =============================================================================

  defp hubspot_api do
    Application.get_env(:social_scribe, :hubspot_api, SocialScribe.CRM.HubSpot.Api)
  end

  defp salesforce_api do
    Application.get_env(:social_scribe, :salesforce_api, SocialScribe.CRM.Salesforce.Api)
  end
end
