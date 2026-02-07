defmodule SocialScribe.ChatAI do
  @moduledoc """
  AI integration for chat, using Google Gemini for multi-turn conversations.

  This module handles:
  - Resolving contacts from message metadata
  - Gathering meeting context for contacts
  - Fetching CRM data from HubSpot/Salesforce
  - Building Gemini multi-turn payloads
  - Generating AI responses
  - Generating thread titles
  """

  @behaviour SocialScribe.ChatAIApi

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias SocialScribe.Chat
  alias SocialScribe.Contacts
  alias SocialScribe.Contacts.Contact
  alias SocialScribe.Accounts
  alias SocialScribe.Meetings.Meeting

  require Logger

  @gemini_model "gemini-2.0-flash-lite"
  @gemini_api_base_url "https://generativelanguage.googleapis.com/v1beta/models"
  @max_meetings 10

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Generates an AI response for a user message in a chat thread.

  Steps:
  1. Save user message
  2. Resolve contact from metadata
  3. Gather CRM data and meeting context
  4. Build multi-turn Gemini payload
  5. Call Gemini API
  6. Save assistant message
  7. Generate thread title if first message

  Returns {:ok, response_content, response_metadata} or {:error, reason}
  """
  @impl SocialScribe.ChatAIApi
  def generate_response(thread, user, content, metadata) do
    with {:ok, user_message} <- Chat.create_user_message(thread, content, metadata),
         {:ok, contact} <- resolve_contact_from_metadata(metadata),
         {:ok, context} <- gather_context(user, contact),
         messages <- Chat.list_messages(thread),
         {:ok, response} <- call_gemini_chat(context, messages, content),
         response_metadata <- build_response_metadata(context),
         {:ok, _assistant_message} <- Chat.create_assistant_message(thread, response, response_metadata) do
      # Generate title if this is the first user message
      maybe_generate_title(thread, user_message)

      {:ok, response, response_metadata}
    end
  end

  @doc """
  Generates a title for a thread based on its messages.
  """
  @impl SocialScribe.ChatAIApi
  def generate_thread_title(thread) do
    messages = Chat.list_messages(thread)

    case messages do
      [] ->
        {:ok, "New Chat"}

      _ ->
        first_user_msg = Enum.find(messages, &(&1.role == "user"))
        first_assistant_msg = Enum.find(messages, &(&1.role == "assistant"))

        if first_user_msg do
          generate_title_from_messages(first_user_msg, first_assistant_msg)
        else
          {:ok, "New Chat"}
        end
    end
  end

  # =============================================================================
  # Contact Resolution
  # =============================================================================

  @doc """
  Resolves a contact from message metadata.
  Returns {:ok, contact} or {:error, :no_contact_tagged}.
  """
  def resolve_contact_from_metadata(%{"mentions" => [%{"contact_id" => id} | _]}) do
    case Contacts.get_contact(id) do
      nil -> {:error, :contact_not_found}
      contact -> {:ok, contact}
    end
  end

  def resolve_contact_from_metadata(%{mentions: [%{contact_id: id} | _]}) do
    case Contacts.get_contact(id) do
      nil -> {:error, :contact_not_found}
      contact -> {:ok, contact}
    end
  end

  def resolve_contact_from_metadata(_), do: {:error, :no_contact_tagged}

  # =============================================================================
  # Context Gathering
  # =============================================================================

  defp gather_context(user, contact) do
    crm_data = gather_crm_data(user, contact)
    meetings = find_meetings_for_contact(user, contact)

    {:ok,
     %{
       contact: contact,
       crm_data: crm_data,
       meetings: meetings
     }}
  end

  defp gather_crm_data(user, contact) do
    # Try HubSpot first, then Salesforce
    case get_hubspot_contact_data(user, contact.email) do
      {:ok, data} when not is_nil(data) ->
        data

      _ ->
        case get_salesforce_contact_data(user, contact.email) do
          {:ok, data} -> data
          _ -> nil
        end
    end
  end

  defp get_hubspot_contact_data(user, email) do
    case Accounts.get_user_credential(user.id, "hubspot") do
      nil ->
        {:error, :no_hubspot_credential}

      credential ->
        hubspot_api().search_contacts(credential, email)
        |> case do
          {:ok, [contact | _]} -> {:ok, contact}
          {:ok, []} -> {:ok, nil}
          error -> error
        end
    end
  end

  defp get_salesforce_contact_data(user, email) do
    case Accounts.get_user_credential(user.id, "salesforce") do
      nil ->
        {:error, :no_salesforce_credential}

      credential ->
        salesforce_api().search_contacts(credential, email)
        |> case do
          {:ok, [contact | _]} -> {:ok, contact}
          {:ok, []} -> {:ok, nil}
          error -> error
        end
    end
  end

  @doc """
  Finds meetings where a contact (by email) was an attendee.
  Returns up to @max_meetings most recent meetings.
  """
  def find_meetings_for_contact(user, %Contact{email: email}) when is_binary(email) do
    # Get meetings from calendar events where the contact's email is in attendees
    Meeting
    |> join(:inner, [m], ce in assoc(m, :calendar_event))
    |> where([m, ce], ce.user_id == ^user.id)
    |> where([m, ce], fragment("EXISTS (SELECT 1 FROM unnest(?) AS a WHERE a->>'email' = ?)", ce.attendees, ^email))
    |> order_by([m, ce], desc: m.recorded_at)
    |> limit(@max_meetings)
    |> preload([:meeting_transcript, :meeting_participants, :calendar_event])
    |> Repo.all()
  end

  def find_meetings_for_contact(_user, _contact), do: []

  # =============================================================================
  # Gemini API Integration
  # =============================================================================

  defp call_gemini_chat(context, thread_messages, current_question) do
    api_key = Application.get_env(:social_scribe, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, {:config_error, "Gemini API key is missing"}}
    else
      payload = build_gemini_payload(context, thread_messages, current_question)
      path = "/#{@gemini_model}:generateContent?key=#{api_key}"

      case Tesla.post(client(), path, payload) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          extract_gemini_response(body)

        {:ok, %Tesla.Env{status: status, body: error_body}} ->
          Logger.error("Gemini API error: #{status} - #{inspect(error_body)}")
          {:error, {:api_error, status, error_body}}

        {:error, reason} ->
          Logger.error("Gemini HTTP error: #{inspect(reason)}")
          {:error, {:http_error, reason}}
      end
    end
  end

  defp build_gemini_payload(context, thread_messages, current_question) do
    system_context = build_system_context(context)

    # Start with system context injection
    contents = [
      %{role: "user", parts: [%{text: system_context}]},
      %{role: "model", parts: [%{text: "I understand. I'll answer questions based only on the provided context about this contact."}]}
    ]

    # Add thread history (excluding the current message which was just saved)
    # Filter out the current question if it's already in thread_messages
    history_messages =
      thread_messages
      |> Enum.reject(fn msg -> msg.content == current_question && msg.role == "user" end)

    thread_contents =
      Enum.map(history_messages, fn msg ->
        role = if msg.role == "user", do: "user", else: "model"
        %{role: role, parts: [%{text: msg.content}]}
      end)

    # Add current question
    current = %{role: "user", parts: [%{text: current_question}]}

    %{contents: contents ++ thread_contents ++ [current]}
  end

  defp build_system_context(context) do
    contact = context.contact
    crm_data = context.crm_data
    meetings = context.meetings

    """
    You are a helpful assistant that answers questions about business contacts based on meeting history and CRM data.

    RULES:
    - Be concise and direct
    - Base your answers ONLY on the context provided below
    - If information is not in the meeting transcripts or contact data, clearly state that you don't have that information
    - Never guess, infer, or make up information
    - When referencing a meeting, use this format: [Meeting: {title} ({date})](meeting:{meeting_id})
    - Format responses in markdown

    CONTACT INFORMATION:
    #{format_contact_info(contact, crm_data)}

    MEETING HISTORY (most recent first, last #{length(meetings)} meetings):
    #{format_meetings(meetings)}
    """
  end

  defp format_contact_info(contact, nil) do
    """
    Name: #{contact.name || "Unknown"}
    Email: #{contact.email}
    """
  end

  defp format_contact_info(contact, crm_data) do
    """
    Name: #{crm_data[:display_name] || contact.name || "Unknown"}
    Email: #{contact.email}
    Company: #{crm_data[:company] || "Unknown"}
    Title: #{crm_data[:jobtitle] || crm_data[:title] || "Unknown"}
    Phone: #{crm_data[:phone] || "Unknown"}
    """
  end

  defp format_meetings([]), do: "No meetings found with this contact."

  defp format_meetings(meetings) do
    meetings
    |> Enum.map(&format_single_meeting/1)
    |> Enum.join("\n\n---\n\n")
  end

  defp format_single_meeting(meeting) do
    transcript_text =
      case meeting.meeting_transcript do
        nil -> "No transcript available"
        transcript -> transcript.transcript_text || "No transcript available"
      end

    participants =
      case meeting.meeting_participants do
        nil -> ""
        [] -> ""
        participants ->
          names = Enum.map(participants, & &1.name) |> Enum.join(", ")
          "Participants: #{names}"
      end

    date = if meeting.recorded_at, do: Calendar.strftime(meeting.recorded_at, "%Y-%m-%d"), else: "Unknown date"

    """
    ### Meeting: #{meeting.title || "Untitled Meeting"}
    ID: #{meeting.id}
    Date: #{date}
    Duration: #{format_duration(meeting.duration_seconds)}
    #{participants}

    Transcript:
    #{transcript_text}
    """
  end

  defp format_duration(nil), do: "Unknown"
  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    "#{minutes} minutes"
  end
  defp format_duration(_), do: "Unknown"

  defp extract_gemini_response(body) do
    text_path = [
      "candidates",
      Access.at(0),
      "content",
      "parts",
      Access.at(0),
      "text"
    ]

    case get_in(body, text_path) do
      nil -> {:error, {:parsing_error, "No text content found in Gemini response", body}}
      text_content -> {:ok, text_content}
    end
  end

  defp build_response_metadata(context) do
    meeting_refs =
      context.meetings
      |> Enum.map(fn meeting ->
        %{
          "meeting_id" => meeting.id,
          "title" => meeting.title,
          "date" => if(meeting.recorded_at, do: Calendar.strftime(meeting.recorded_at, "%Y-%m-%d"), else: nil)
        }
      end)

    %{"meeting_refs" => meeting_refs}
  end

  # =============================================================================
  # Title Generation
  # =============================================================================

  defp maybe_generate_title(thread, user_message) do
    # Only generate title if it's nil and this is the first user message
    if is_nil(thread.title) do
      case Chat.get_first_user_message(thread) do
        %{id: id} when id == user_message.id ->
          # This is the first user message, generate title after response
          Task.start(fn ->
            Process.sleep(500) # Small delay to ensure response is saved
            case generate_thread_title(thread) do
              {:ok, title} -> Chat.update_thread(thread, %{title: title})
              _ -> :ok
            end
          end)

        _ ->
          :ok
      end
    end
  end

  defp generate_title_from_messages(user_message, assistant_message) do
    api_key = Application.get_env(:social_scribe, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:ok, truncate_for_title(user_message.content)}
    else
      prompt = """
      Generate a short, concise title (max 6 words) for a chat conversation.
      The title should capture the main topic of the discussion.

      User's question: #{user_message.content}
      #{if assistant_message, do: "Assistant's response: #{String.slice(assistant_message.content, 0, 500)}", else: ""}

      Respond with ONLY the title, no quotes, no explanation.
      """

      payload = %{
        contents: [%{parts: [%{text: prompt}]}]
      }

      path = "/#{@gemini_model}:generateContent?key=#{api_key}"

      case Tesla.post(client(), path, payload) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          case extract_gemini_response(body) do
            {:ok, title} -> {:ok, String.trim(title)}
            _ -> {:ok, truncate_for_title(user_message.content)}
          end

        _ ->
          {:ok, truncate_for_title(user_message.content)}
      end
    end
  end

  defp truncate_for_title(content) do
    content
    |> String.slice(0, 50)
    |> String.trim()
    |> then(fn s ->
      if String.length(content) > 50, do: s <> "...", else: s
    end)
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @gemini_api_base_url},
      Tesla.Middleware.JSON
    ])
  end

  # API module getters for mocking
  defp hubspot_api do
    Application.get_env(:social_scribe, :hubspot_api, SocialScribe.HubspotApi)
  end

  defp salesforce_api do
    Application.get_env(:social_scribe, :salesforce_api, SocialScribe.SalesforceApi)
  end
end
