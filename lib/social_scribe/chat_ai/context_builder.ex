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
  alias SocialScribe.Contacts.Contact
  alias SocialScribe.Meetings.Meeting
  alias SocialScribe.Calendar.CalendarEventAttendee

  @max_meetings Application.compile_env(:social_scribe, :chat_max_meetings, 10)

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Gathers context for a user and contact.

  Returns a map with:
  - `:contact` - The contact struct (or nil)
  - `:crm_data` - CRM data from HubSpot/Salesforce (or nil)
  - `:meetings` - List of relevant meetings
  """
  def gather_context(%User{} = user, %Contact{} = contact) do
    crm_data = gather_crm_data(user, contact)
    meetings = find_meetings_for_contact(user, contact)

    {:ok,
     %{
       contact: contact,
       crm_data: crm_data,
       meetings: meetings
     }}
  end

  def gather_context(%User{} = user, nil) do
    meetings = find_recent_meetings_for_user(user)

    {:ok,
     %{
       contact: nil,
       crm_data: nil,
       meetings: meetings
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
    case Credentials.get_user_credential(user, "hubspot") do
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
    case Credentials.get_user_credential(user, "salesforce") do
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
  # API Module Getters (for mocking)
  # =============================================================================

  defp hubspot_api do
    Application.get_env(:social_scribe, :hubspot_api, SocialScribe.CRM.HubSpot.Api)
  end

  defp salesforce_api do
    Application.get_env(:social_scribe, :salesforce_api, SocialScribe.CRM.Salesforce.Api)
  end
end
