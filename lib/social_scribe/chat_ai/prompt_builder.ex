defmodule SocialScribe.ChatAI.PromptBuilder do
  @moduledoc """
  Builds prompts and payloads for the Gemini AI API.

  This module handles:
  - Building system context from meetings and CRM data
  - Formatting meeting transcripts for AI consumption
  - Building Gemini API payloads
  """

  alias SocialScribe.Contacts.Contact
  alias SocialScribe.Meetings.{Meeting, MeetingTranscript, MeetingParticipant}
  alias SocialScribe.Chat.ChatMessage
  alias SocialScribe.TranscriptParser

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
  def build_system_context(%{contact: %Contact{} = contact, crm_data: crm_data, meetings: meetings})
      when is_list(meetings) do
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

  def build_system_context(%{contact: nil, crm_data: nil, meetings: meetings})
      when is_list(meetings) do
    """
    You are a helpful assistant that answers questions about the user's recent meetings.

    RULES:
    - Be concise and direct
    - Base your answers ONLY on the context provided below
    - If information is not in the meeting transcripts, clearly state that you don't have that information
    - Never guess, infer, or make up information
    - When referencing a meeting, use this format: [Meeting: {title} ({date})](meeting:{meeting_id})
    - Format responses in markdown

    RECENT MEETING HISTORY (most recent first, last #{length(meetings)} meetings):
    #{format_meetings(meetings)}
    """
  end

  # =============================================================================
  # Response Metadata Building
  # =============================================================================

  @doc """
  Builds metadata for the AI response including meeting references.
  """
  def build_response_metadata(%{meetings: meetings}) when is_list(meetings) do
    meeting_refs =
      meetings
      |> Enum.map(fn %Meeting{id: id, title: title, recorded_at: recorded_at} ->
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

    %{"meeting_refs" => meeting_refs}
  end

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

  defp format_meetings([]), do: "No meetings found with this contact."

  defp format_meetings(meetings) do
    meetings
    |> Enum.map(&format_single_meeting/1)
    |> Enum.join("\n\n---\n\n")
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
