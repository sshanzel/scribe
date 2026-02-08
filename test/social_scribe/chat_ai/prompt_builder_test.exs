defmodule SocialScribe.ChatAI.PromptBuilderTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.ChatAI.PromptBuilder
  alias SocialScribe.Contacts.Contact
  alias SocialScribe.Meetings.{Meeting, MeetingTranscript, MeetingParticipant}

  # =============================================================================
  # Prompt Snapshot Tests
  # =============================================================================

  describe "build_system_context/1 prompt snapshots" do
    test "contact with CRM data" do
      {_name, context} = build_scenario_contact_with_crm()
      prompt = PromptBuilder.build_system_context(context)

      expected = """
      You are a helpful assistant that answers questions about business contacts based on meeting history and CRM data.

      RULES:
      - Be concise and direct
      - Base your answers ONLY on the context provided below
      - If information is not in the meeting transcripts or contact data, clearly state that you don't have that information
      - Never guess, infer, or make up information
      - When referencing a meeting, use this format: [Meeting: {title} ({date})](meeting:{meeting_id})
      - Format responses in markdown

      CONTACT INFORMATION:
      Name: John Doe
      Email: john@example.com
      Company: Acme Corp
      Title: VP of Sales
      Phone: 555-1234


      MEETING HISTORY (most recent first, last 1 meetings):
      ### Meeting: Q1 Budget Review
      ID: 1
      Date: 2025-01-15
      Duration: 30 minutes
      Participants: John Doe, Jane Smith

      Transcript:
      John: Hello everyone, let's get started.
      Jane: Sounds good, I have the agenda ready.


      """

      assert prompt == expected
    end

    test "contact without CRM data" do
      {_name, context} = build_scenario_contact_without_crm()
      prompt = PromptBuilder.build_system_context(context)

      expected = """
      You are a helpful assistant that answers questions about business contacts based on meeting history and CRM data.

      RULES:
      - Be concise and direct
      - Base your answers ONLY on the context provided below
      - If information is not in the meeting transcripts or contact data, clearly state that you don't have that information
      - Never guess, infer, or make up information
      - When referencing a meeting, use this format: [Meeting: {title} ({date})](meeting:{meeting_id})
      - Format responses in markdown

      CONTACT INFORMATION:
      Name: Jane Smith
      Email: jane@example.com


      MEETING HISTORY (most recent first, last 1 meetings):
      ### Meeting: Product Demo
      ID: 1
      Date: 2025-01-20
      Duration: 30 minutes
      Participants: John Doe, Jane Smith

      Transcript:
      John: Hello everyone, let's get started.
      Jane: Sounds good, I have the agenda ready.


      """

      assert prompt == expected
    end

    test "CRM data only (no local contact)" do
      {_name, context} = build_scenario_crm_only()
      prompt = PromptBuilder.build_system_context(context)

      expected = """
      You are a helpful assistant that answers questions about business contacts based on meeting history and CRM data.

      RULES:
      - Be concise and direct
      - Base your answers ONLY on the context provided below
      - If information is not in the meeting transcripts or contact data, clearly state that you don't have that information
      - Never guess, infer, or make up information
      - When referencing a meeting, use this format: [Meeting: {title} ({date})](meeting:{meeting_id})
      - Format responses in markdown

      CONTACT INFORMATION:
      Name: Bob Wilson
      Email: bob@techcorp.com
      Company: TechCorp
      Title: CTO
      Phone: 555-9999
      Department: Engineering


      MEETING HISTORY (most recent first, last 1 meetings):
      ### Meeting: Technical Review
      ID: 1
      Date: 2025-01-25
      Duration: 30 minutes
      Participants: John Doe, Jane Smith

      Transcript:
      John: Hello everyone, let's get started.
      Jane: Sounds good, I have the agenda ready.


      """

      assert prompt == expected
    end

    test "no contact, no CRM data (recent meetings only)" do
      {_name, context} = build_scenario_recent_meetings_only()
      prompt = PromptBuilder.build_system_context(context)

      expected = """
      You are a helpful assistant that answers questions about the user's recent meetings.

      RULES:
      - Be concise and direct
      - Base your answers ONLY on the context provided below
      - If information is not in the meeting transcripts, clearly state that you don't have that information
      - Never guess, infer, or make up information
      - When referencing a meeting, use this format: [Meeting: {title} ({date})](meeting:{meeting_id})
      - Format responses in markdown

      RECENT MEETING HISTORY (most recent first, last 2 meetings):
      ### Meeting: Team Standup
      ID: 1
      Date: 2025-01-28
      Duration: 30 minutes
      Participants: John Doe, Jane Smith

      Transcript:
      John: Hello everyone, let's get started.
      Jane: Sounds good, I have the agenda ready.


      ---

      ### Meeting: Sprint Planning
      ID: 2
      Date: 2025-01-27
      Duration: 30 minutes
      Participants: John Doe, Jane Smith

      Transcript:
      John: Hello everyone, let's get started.
      Jane: Sounds good, I have the agenda ready.


      """

      assert prompt == expected
    end

    test "name-matched meetings (no email match)" do
      {_name, context} = build_scenario_name_matched_meetings()
      prompt = PromptBuilder.build_system_context(context)

      expected = """
      You are a helpful assistant that answers questions about business contacts based on meeting history and CRM data.

      RULES:
      - Be concise and direct
      - Base your answers ONLY on the context provided below
      - If information is not in the meeting transcripts or contact data, clearly state that you don't have that information
      - Never guess, infer, or make up information
      - When referencing a meeting, use this format: [Meeting: {title} ({date})](meeting:{meeting_id})
      - Format responses in markdown

      CONTACT INFORMATION:
      Name: Sarah Chen
      Email: sarah@newcompany.com
      Company: New Company Inc
      Title: Unknown
      Phone: Unknown


      MEETING HISTORY (most recent first, last 0 meetings):
      No meetings found with this contact.

      POTENTIAL MEETINGS (matched by first name only - USE WITH CAUTION):
      ⚠️ IMPORTANT: No meetings were found with an exact email match for this contact.
      The meetings below were found by matching the contact's first name to meeting participants.
      This is NOT a confirmed match - different people may share the same first name.

      Guidelines:
      1. Only use information from these meetings if the context (topic, company, participants) clearly matches the contact
      2. Look for the meeting with strong contextual evidence when reviewing the details against the questions being asked to determine if it's likely to be the same person
      3. The email mismatched which is why we should not use it to compare whether this was the user or not
      4. Mention in your response that these meetings were based on the participant's name only and may not be the same person, so the information should be used with caution
      5. If there is any uncertainty, it's better to state that you don't have enough information rather than risk providing inaccurate information

      ### Meeting: Q4 Planning with Sarah
      ID: 1
      Date: 2025-01-10
      Duration: 30 minutes
      Participants: John Doe, Jane Smith

      Transcript:
      John: Hello everyone, let's get started.
      Jane: Sounds good, I have the agenda ready.


      ---

      ### Meeting: Follow-up with Sarah
      ID: 2
      Date: 2025-01-05
      Duration: 30 minutes
      Participants: John Doe, Jane Smith

      Transcript:
      John: Hello everyone, let's get started.
      Jane: Sounds good, I have the agenda ready.


      """

      assert prompt == expected
    end

    test "no meetings at all" do
      {_name, context} = build_scenario_no_meetings()
      prompt = PromptBuilder.build_system_context(context)

      expected = """
      You are a helpful assistant that answers questions about business contacts based on meeting history and CRM data.

      RULES:
      - Be concise and direct
      - Base your answers ONLY on the context provided below
      - If information is not in the meeting transcripts or contact data, clearly state that you don't have that information
      - Never guess, infer, or make up information
      - When referencing a meeting, use this format: [Meeting: {title} ({date})](meeting:{meeting_id})
      - Format responses in markdown

      CONTACT INFORMATION:
      Name: New Contact
      Email: new@example.com


      MEETING HISTORY (most recent first, last 0 meetings):
      No meetings found with this contact.

      """

      assert prompt == expected
    end
  end

  # =============================================================================
  # Scenario Builders
  # =============================================================================

  defp build_scenario_contact_with_crm do
    contact = %Contact{
      id: 1,
      name: "John Doe",
      email: "john@example.com"
    }

    crm_data = %{
      "display_name" => "John Doe",
      "company" => "Acme Corp",
      "jobtitle" => "VP of Sales",
      "phone" => "555-1234"
    }

    context = %{
      contact: contact,
      crm_data: crm_data,
      meetings: [sample_meeting(1, "Q1 Budget Review", ~U[2025-01-15 10:00:00Z])],
      name_matched_meetings: []
    }

    {"Contact with CRM data", context}
  end

  defp build_scenario_contact_without_crm do
    contact = %Contact{
      id: 1,
      name: "Jane Smith",
      email: "jane@example.com"
    }

    context = %{
      contact: contact,
      crm_data: nil,
      meetings: [sample_meeting(1, "Product Demo", ~U[2025-01-20 14:00:00Z])],
      name_matched_meetings: []
    }

    {"Contact without CRM data", context}
  end

  defp build_scenario_crm_only do
    crm_data = %{
      "display_name" => "Bob Wilson",
      "email" => "bob@techcorp.com",
      "company" => "TechCorp",
      "title" => "CTO",
      "phone" => "555-9999",
      "department" => "Engineering"
    }

    context = %{
      contact: nil,
      crm_data: crm_data,
      meetings: [sample_meeting(1, "Technical Review", ~U[2025-01-25 09:00:00Z])],
      name_matched_meetings: []
    }

    {"CRM data only (no local contact)", context}
  end

  defp build_scenario_recent_meetings_only do
    context = %{
      contact: nil,
      crm_data: nil,
      meetings: [
        sample_meeting(1, "Team Standup", ~U[2025-01-28 10:00:00Z]),
        sample_meeting(2, "Sprint Planning", ~U[2025-01-27 14:00:00Z])
      ],
      name_matched_meetings: []
    }

    {"No contact, no CRM data (recent meetings only)", context}
  end

  defp build_scenario_name_matched_meetings do
    crm_data = %{
      "display_name" => "Sarah Chen",
      "email" => "sarah@newcompany.com",
      "company" => "New Company Inc"
    }

    context = %{
      contact: nil,
      crm_data: crm_data,
      meetings: [],
      name_matched_meetings: [
        sample_meeting(1, "Q4 Planning with Sarah", ~U[2025-01-10 11:00:00Z]),
        sample_meeting(2, "Follow-up with Sarah", ~U[2025-01-05 15:00:00Z])
      ]
    }

    {"Name-matched meetings (no email match)", context}
  end

  defp build_scenario_no_meetings do
    contact = %Contact{
      id: 1,
      name: "New Contact",
      email: "new@example.com"
    }

    context = %{
      contact: contact,
      crm_data: nil,
      meetings: [],
      name_matched_meetings: []
    }

    {"No meetings at all", context}
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp sample_meeting(id, title, recorded_at) do
    %Meeting{
      id: id,
      title: title,
      recorded_at: recorded_at,
      duration_seconds: 1800,
      meeting_transcript: %MeetingTranscript{
        content: %{
          "data" => [
            %{
              "speaker" => "John",
              "words" => [
                %{"text" => "Hello everyone,", "start_timestamp" => 5.0},
                %{"text" => "let's get started.", "start_timestamp" => 6.5}
              ]
            },
            %{
              "speaker" => "Jane",
              "words" => [
                %{"text" => "Sounds good,", "start_timestamp" => 10.0},
                %{"text" => "I have the agenda ready.", "start_timestamp" => 11.5}
              ]
            }
          ]
        }
      },
      meeting_participants: [
        %MeetingParticipant{name: "John Doe", is_host: true},
        %MeetingParticipant{name: "Jane Smith", is_host: false}
      ]
    }
  end
end
