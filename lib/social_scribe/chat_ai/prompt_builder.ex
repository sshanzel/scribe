defmodule SocialScribe.ChatAI.PromptBuilder do
  @moduledoc """
  Builds prompts and payloads for the Gemini AI API.

  This module handles:
  - Building system context from meetings and CRM data
  - Formatting meeting transcripts for AI consumption
  - Building Gemini API payloads
  - Meeting link format definition (used by both AI prompts and rendering)
  """

  alias SocialScribe.Contacts.Contact
  alias SocialScribe.Meetings.{Meeting, MeetingTranscript, MeetingParticipant}
  alias SocialScribe.Chat.ChatMessage
  alias SocialScribe.TranscriptParser

  # =============================================================================
  # Meeting Link Format
  # =============================================================================

  @meeting_link_regex ~r/\[([^\]]+)\]\(meeting:(\d+)\)/
  @meeting_link_instruction """
  - When referencing a meeting, mention the date naturally as a link using format: [Month Day, Year](meeting:{meeting_id})
    Example: "In a meeting on [January 15, 2025](meeting:123), they discussed..." or "During the [November 3, 2025](meeting:456) call..."\
  """

  @doc """
  Returns the regex pattern for matching meeting links in AI responses.
  Format: [link text](meeting:id)
  """
  def meeting_link_regex, do: @meeting_link_regex

  @doc """
  Returns the instruction text for the AI on how to format meeting links.
  """
  def meeting_link_instruction, do: @meeting_link_instruction

  # =============================================================================
  # Gemini Payload Building
  # =============================================================================

  @doc """
  Builds a Gemini API payload for multi-turn chat.
  """
  def build_gemini_payload(context, thread_messages, current_question)
      when is_map(context) and is_list(thread_messages) and is_binary(current_question) do
    system_context = build_system_context(context)

    # Start with system context injection
    contents = [
      %{role: "user", parts: [%{text: system_context}]},
      %{
        role: "model",
        parts: [
          %{
            text:
              "I understand. I'll answer questions based only on the provided context about this contact."
          }
        ]
      }
    ]

    # Add thread history (excluding the current message which was just saved)
    history_messages =
      thread_messages
      |> Enum.reject(fn
        %ChatMessage{content: content, role: "user"} -> content == current_question
        _ -> false
      end)

    thread_contents =
      Enum.map(history_messages, fn %ChatMessage{role: role, content: content} ->
        gemini_role = if role == "user", do: "user", else: "model"
        %{role: gemini_role, parts: [%{text: content}]}
      end)

    # Add current question
    current = %{role: "user", parts: [%{text: current_question}]}

    %{contents: contents ++ thread_contents ++ [current]}
  end

  # =============================================================================
  # System Context Building
  # =============================================================================

  @doc """
  Builds the system context prompt from gathered context.
  """
  def build_system_context(%{
        contact: contact,
        crm_data: crm_data,
        meetings: meetings,
        name_matched_meetings: name_matched
      })
      when is_list(meetings) do
    has_contact_context = contact != nil or is_map(crm_data)

    build_prompt(%{
      has_contact_context: has_contact_context,
      contact_info: format_contact_section(contact, crm_data),
      meetings: meetings,
      name_matched_meetings: name_matched || []
    })
  end

  # Fallback for old context format without name_matched_meetings
  def build_system_context(%{contact: contact, crm_data: crm_data, meetings: meetings}) do
    build_system_context(%{
      contact: contact,
      crm_data: crm_data,
      meetings: meetings,
      name_matched_meetings: []
    })
  end

  defp build_prompt(%{
         has_contact_context: has_contact_context,
         contact_info: contact_info,
         meetings: meetings,
         name_matched_meetings: name_matched
       }) do
    {intro, info_source, meeting_label} = context_parts(has_contact_context)

    """
    You are a helpful assistant that answers questions about #{intro}.

    RULES:
    - Be concise and direct
    - Base your answers ONLY on the context provided below
    - If information is not in the meeting transcripts#{info_source}, clearly state that you don't have that information
    - Never guess, infer, or make up information
    #{@meeting_link_instruction}
    - Format responses in markdown
    #{contact_info}
    #{meeting_label} HISTORY (most recent first, last #{length(meetings)} meetings):
    #{format_meetings(meetings)}
    #{format_name_matched_meetings(name_matched)}
    """
  end

  defp context_parts(true = _has_contact),
    do: {"business contacts based on meeting history and CRM data", " or contact data", "MEETING"}

  defp context_parts(false = _has_contact),
    do: {"the user's recent meetings", "", "RECENT MEETING"}

  defp format_contact_section(%Contact{} = contact, crm_data) do
    """

    CONTACT INFORMATION:
    #{format_contact_info(contact, crm_data)}
    """
  end

  defp format_contact_section(nil, crm_data) when is_map(crm_data) do
    """

    CONTACT INFORMATION:
    #{format_crm_contact_info(crm_data)}
    """
  end

  defp format_contact_section(nil, nil), do: ""

  # =============================================================================
  # Response Metadata Building
  # =============================================================================

  @doc """
  Builds metadata for the AI response including meeting references.
  Combines email-matched and name-matched meetings so all can be linked.
  """
  def build_response_metadata(%{meetings: meetings, name_matched_meetings: name_matched})
      when is_list(meetings) do
    all_meetings = meetings ++ (name_matched || [])
    %{"meeting_refs" => build_meeting_refs(all_meetings)}
  end

  def build_response_metadata(%{meetings: meetings}) when is_list(meetings) do
    %{"meeting_refs" => build_meeting_refs(meetings)}
  end

  defp build_meeting_refs(meetings) when is_list(meetings) do
    Enum.map(meetings, fn %Meeting{id: id, title: title, recorded_at: recorded_at} ->
      date =
        case recorded_at do
          %DateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d")
          %NaiveDateTime{} = ndt -> Calendar.strftime(ndt, "%Y-%m-%d")
          nil -> nil
        end

      %{
        "meeting_id" => id,
        "title" => title,
        "date" => date
      }
    end)
  end

  defp build_meeting_refs(_), do: []

  # =============================================================================
  # Formatting Helpers
  # =============================================================================

  defp format_contact_info(%Contact{name: name, email: email}, nil) do
    """
    Name: #{name || "Unknown"}
    Email: #{email}
    """
  end

  defp format_contact_info(%Contact{name: name, email: email}, crm_data) when is_map(crm_data) do
    """
    Name: #{crm_data[:display_name] || crm_data["display_name"] || name || "Unknown"}
    Email: #{email}
    Company: #{crm_data[:company] || crm_data["company"] || "Unknown"}
    Title: #{crm_data[:jobtitle] || crm_data["jobtitle"] || crm_data[:title] || crm_data["title"] || "Unknown"}
    Phone: #{crm_data[:phone] || crm_data["phone"] || "Unknown"}
    """
  end

  defp format_crm_contact_info(crm_data) when is_map(crm_data) do
    name = crm_data["display_name"] || crm_data[:display_name] || "Unknown"
    email = crm_data["email"] || crm_data[:email] || "Unknown"
    company = crm_data["company"] || crm_data[:company] || "Unknown"

    title =
      crm_data["title"] || crm_data[:title] || crm_data["jobtitle"] || crm_data[:jobtitle] ||
        "Unknown"

    phone = crm_data["phone"] || crm_data[:phone] || "Unknown"
    department = crm_data["department"] || crm_data[:department]

    base = """
    Name: #{name}
    Email: #{email}
    Company: #{company}
    Title: #{title}
    Phone: #{phone}
    """

    if department do
      base <> "Department: #{department}\n"
    else
      base
    end
  end

  defp format_meetings([]), do: "No meetings found with this contact."

  defp format_meetings(meetings) do
    meetings
    |> Enum.map(&format_single_meeting/1)
    |> Enum.join("\n\n---\n\n")
  end

  defp format_name_matched_meetings([]), do: ""

  defp format_name_matched_meetings(meetings) when is_list(meetings) do
    """

    POTENTIAL MEETINGS (matched by first name only - USE WITH CAUTION):
    ⚠️ IMPORTANT: No meetings were found with an exact email match for this contact.
    The meetings below were found by matching the contact's first name to meeting participants.
    This is NOT a confirmed match - different people may share the same first name.

    Guidelines:
    1. Only use information from these meetings if the context (topic, company, participants) clearly matches the contact
    2. Look for the meeting with strong contextual evidence when reviewing the details against the questions being asked to determine if it's likely to be the same person
    3. The email mismatched which is why we should not use it to compare whether this was the user or not
    4. Mention in your response that these meetings were based on the participant's name only and may not be the same person in a concise manner
    5. If there is any uncertainty, it's better to state that you don't have enough information rather than risk providing inaccurate information

    #{format_meetings(meetings)}
    """
  end

  defp format_single_meeting(%Meeting{} = meeting) do
    transcript_text =
      case meeting.meeting_transcript do
        nil -> "No transcript available"
        %MeetingTranscript{content: content} -> format_transcript_content(content)
      end

    participants =
      case meeting.meeting_participants do
        nil ->
          ""

        [] ->
          ""

        [%MeetingParticipant{} | _] = participants ->
          names = Enum.map(participants, & &1.name) |> Enum.join(", ")
          "Participants: #{names}"
      end

    date =
      case meeting.recorded_at do
        %DateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d")
        %NaiveDateTime{} = ndt -> Calendar.strftime(ndt, "%Y-%m-%d")
        nil -> "Unknown date"
      end

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

  defp format_transcript_content(nil), do: "No transcript available"

  defp format_transcript_content(%{"data" => data}) when is_list(data) do
    TranscriptParser.format_segments_for_display(data)
  end

  defp format_transcript_content(_), do: "No transcript available"

  defp format_duration(nil), do: "Unknown"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    "#{minutes} minutes"
  end

  defp format_duration(_), do: "Unknown"
end
