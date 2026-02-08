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
      - When referencing a meeting, mention the date naturally as a link using format: [Month Day, Year](meeting:{meeting_id})
        Example: "In a meeting on [January 15, 2025](meeting:123), they discussed..." or "During the [November 3, 2025](meeting:456) call..."
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
      - When referencing a meeting, mention the date naturally as a link using format: [Month Day, Year](meeting:{meeting_id})
        Example: "In a meeting on [January 15, 2025](meeting:123), they discussed..." or "During the [November 3, 2025](meeting:456) call..."
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
      - When referencing a meeting, mention the date naturally as a link using format: [Month Day, Year](meeting:{meeting_id})
        Example: "In a meeting on [January 15, 2025](meeting:123), they discussed..." or "During the [November 3, 2025](meeting:456) call..."
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
      - When referencing a meeting, mention the date naturally as a link using format: [Month Day, Year](meeting:{meeting_id})
        Example: "In a meeting on [January 15, 2025](meeting:123), they discussed..." or "During the [November 3, 2025](meeting:456) call..."
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
      - When referencing a meeting, mention the date naturally as a link using format: [Month Day, Year](meeting:{meeting_id})
        Example: "In a meeting on [January 15, 2025](meeting:123), they discussed..." or "During the [November 3, 2025](meeting:456) call..."
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
      3. You can't answer certainly and must say that you found meetings with a contact that matches the name but not the email.
      4. The email mismatched which is why we should not use it to compare whether this was the user or not
      5. Mention in your response that these meetings were based on the participant's name only and may not be the same person in a concise manner
      6. If there is any uncertainty, it's better to state that you don't have enough information rather than risk providing inaccurate information

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
      - When referencing a meeting, mention the date naturally as a link using format: [Month Day, Year](meeting:{meeting_id})
        Example: "In a meeting on [January 15, 2025](meeting:123), they discussed..." or "During the [November 3, 2025](meeting:456) call..."
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
  # build_response_metadata/1
  # =============================================================================

  describe "build_response_metadata/1" do
    test "includes meeting refs from both email and name matched meetings" do
      context = %{
        meetings: [sample_meeting(1, "Email Match", ~U[2025-01-15 10:00:00Z])],
        name_matched_meetings: [sample_meeting(2, "Name Match", ~U[2025-01-10 10:00:00Z])]
      }

      metadata = PromptBuilder.build_response_metadata(context)

      assert length(metadata["meeting_refs"]) == 2
      ids = Enum.map(metadata["meeting_refs"], & &1["meeting_id"])
      assert 1 in ids
      assert 2 in ids
    end

    test "handles empty meetings list" do
      context = %{
        meetings: [],
        name_matched_meetings: []
      }

      metadata = PromptBuilder.build_response_metadata(context)

      assert metadata["meeting_refs"] == []
    end

    test "handles nil name_matched_meetings" do
      context = %{
        meetings: [sample_meeting(1, "Meeting", ~U[2025-01-15 10:00:00Z])],
        name_matched_meetings: nil
      }

      metadata = PromptBuilder.build_response_metadata(context)

      assert length(metadata["meeting_refs"]) == 1
    end

    test "formats dates correctly" do
      context = %{
        meetings: [sample_meeting(1, "Meeting", ~U[2025-12-25 10:00:00Z])],
        name_matched_meetings: []
      }

      metadata = PromptBuilder.build_response_metadata(context)

      [ref] = metadata["meeting_refs"]
      assert ref["date"] == "2025-12-25"
    end

    test "handles meeting with nil recorded_at" do
      meeting = %Meeting{
        id: 1,
        title: "Untitled",
        recorded_at: nil,
        duration_seconds: nil,
        meeting_transcript: nil,
        meeting_participants: []
      }

      context = %{
        meetings: [meeting],
        name_matched_meetings: []
      }

      metadata = PromptBuilder.build_response_metadata(context)

      [ref] = metadata["meeting_refs"]
      assert ref["date"] == nil
    end

    test "fallback for context without name_matched_meetings key" do
      context = %{meetings: [sample_meeting(1, "Meeting", ~U[2025-01-15 10:00:00Z])]}

      metadata = PromptBuilder.build_response_metadata(context)

      assert length(metadata["meeting_refs"]) == 1
    end
  end

  # =============================================================================
  # build_gemini_payload/3
  # =============================================================================

  describe "build_gemini_payload/3" do
    alias SocialScribe.Chat.ChatMessage

    test "builds payload with system context and current question" do
      context = %{
        contact: nil,
        crm_data: nil,
        meetings: [],
        name_matched_meetings: []
      }

      payload = PromptBuilder.build_gemini_payload(context, [], "What is the summary?")

      assert is_map(payload)
      assert is_list(payload.contents)
      # System context + model ack + current question
      assert length(payload.contents) == 3
    end

    test "includes thread history" do
      context = %{
        contact: nil,
        crm_data: nil,
        meetings: [],
        name_matched_meetings: []
      }

      messages = [
        %ChatMessage{role: "user", content: "First question"},
        %ChatMessage{role: "assistant", content: "First answer"}
      ]

      payload = PromptBuilder.build_gemini_payload(context, messages, "Second question")

      # System context + ack + 2 history + current = 5
      assert length(payload.contents) == 5
    end

    test "excludes current question from history if already saved" do
      context = %{
        contact: nil,
        crm_data: nil,
        meetings: [],
        name_matched_meetings: []
      }

      messages = [
        %ChatMessage{role: "user", content: "My question"},
        %ChatMessage{role: "assistant", content: "Previous answer"}
      ]

      payload = PromptBuilder.build_gemini_payload(context, messages, "My question")

      # System + ack + 1 assistant msg (user msg excluded as duplicate) + current = 4
      assert length(payload.contents) == 4
    end

    test "maps assistant role to model" do
      context = %{
        contact: nil,
        crm_data: nil,
        meetings: [],
        name_matched_meetings: []
      }

      messages = [
        %ChatMessage{role: "assistant", content: "I am assistant"}
      ]

      payload = PromptBuilder.build_gemini_payload(context, messages, "Question")

      roles = Enum.map(payload.contents, & &1.role)
      assert "model" in roles
      refute "assistant" in roles
    end
  end

  # =============================================================================
  # Edge Cases
  # =============================================================================

  describe "edge cases" do
    test "handles meeting with no transcript" do
      meeting = %Meeting{
        id: 1,
        title: "No Transcript Meeting",
        recorded_at: ~U[2025-01-15 10:00:00Z],
        duration_seconds: 1800,
        meeting_transcript: nil,
        meeting_participants: []
      }

      context = %{
        contact: nil,
        crm_data: nil,
        meetings: [meeting],
        name_matched_meetings: []
      }

      prompt = PromptBuilder.build_system_context(context)

      assert prompt =~ "No transcript available"
    end

    test "handles meeting with no participants" do
      meeting = %Meeting{
        id: 1,
        title: "Solo Meeting",
        recorded_at: ~U[2025-01-15 10:00:00Z],
        duration_seconds: 1800,
        meeting_transcript: nil,
        meeting_participants: []
      }

      context = %{
        contact: nil,
        crm_data: nil,
        meetings: [meeting],
        name_matched_meetings: []
      }

      prompt = PromptBuilder.build_system_context(context)

      # Should not crash and should not show "Participants:"
      refute prompt =~ "Participants:"
    end

    test "handles meeting with nil duration" do
      meeting = %Meeting{
        id: 1,
        title: "Unknown Duration",
        recorded_at: ~U[2025-01-15 10:00:00Z],
        duration_seconds: nil,
        meeting_transcript: nil,
        meeting_participants: []
      }

      context = %{
        contact: nil,
        crm_data: nil,
        meetings: [meeting],
        name_matched_meetings: []
      }

      prompt = PromptBuilder.build_system_context(context)

      assert prompt =~ "Duration: Unknown"
    end

    test "handles CRM data with atom keys" do
      context = %{
        contact: nil,
        crm_data: %{
          display_name: "John Doe",
          email: "john@example.com",
          company: "Acme",
          title: "CEO",
          phone: "555-0000"
        },
        meetings: [],
        name_matched_meetings: []
      }

      prompt = PromptBuilder.build_system_context(context)

      assert prompt =~ "Name: John Doe"
      assert prompt =~ "Company: Acme"
    end

    test "prefers CRM display_name over contact name" do
      contact = %Contact{
        id: 1,
        name: "John Contact",
        email: "john@example.com"
      }

      crm_data = %{
        "display_name" => "John CRM"
      }

      context = %{
        contact: contact,
        crm_data: crm_data,
        meetings: [],
        name_matched_meetings: []
      }

      prompt = PromptBuilder.build_system_context(context)

      assert prompt =~ "Name: John CRM"
      refute prompt =~ "Name: John Contact"
    end

    test "falls back to contact name when CRM display_name is missing" do
      contact = %Contact{
        id: 1,
        name: "John Contact",
        email: "john@example.com"
      }

      crm_data = %{
        "company" => "Acme"
      }

      context = %{
        contact: contact,
        crm_data: crm_data,
        meetings: [],
        name_matched_meetings: []
      }

      prompt = PromptBuilder.build_system_context(context)

      assert prompt =~ "Name: John Contact"
    end

    test "handles old context format without name_matched_meetings" do
      context = %{
        contact: nil,
        crm_data: nil,
        meetings: []
      }

      # Should not crash
      prompt = PromptBuilder.build_system_context(context)

      assert prompt =~ "RECENT MEETING HISTORY"
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
