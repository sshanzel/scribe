defmodule SocialScribe.ChatAI.ContextBuilderTest do
  use SocialScribe.DataCase, async: true

  import SocialScribe.AccountsFixtures
  import SocialScribe.ContactsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.BotsFixtures

  alias SocialScribe.ChatAI.ContextBuilder
  alias SocialScribe.Contacts

  # =============================================================================
  # extract_first_name/1
  # =============================================================================

  describe "extract_first_name/1" do
    test "extracts first name from full name" do
      assert ContextBuilder.extract_first_name("John Doe") == "John"
    end

    test "extracts first name from name with multiple parts" do
      assert ContextBuilder.extract_first_name("John Michael Doe") == "John"
    end

    test "returns single name as-is" do
      assert ContextBuilder.extract_first_name("John") == "John"
    end

    test "handles extra whitespace" do
      assert ContextBuilder.extract_first_name("  John   Doe  ") == "John"
    end

    test "handles tabs and newlines" do
      assert ContextBuilder.extract_first_name("\tJohn\nDoe") == "John"
    end

    test "returns nil for nil input" do
      assert ContextBuilder.extract_first_name(nil) == nil
    end

    test "returns nil for empty string" do
      assert ContextBuilder.extract_first_name("") == nil
    end

    test "returns nil for whitespace-only string" do
      assert ContextBuilder.extract_first_name("   ") == nil
    end

    test "handles unicode names" do
      assert ContextBuilder.extract_first_name("José García") == "José"
      assert ContextBuilder.extract_first_name("田中 太郎") == "田中"
    end

    test "handles hyphenated first names" do
      assert ContextBuilder.extract_first_name("Mary-Jane Watson") == "Mary-Jane"
    end

    test "handles names with apostrophes" do
      assert ContextBuilder.extract_first_name("O'Brien Smith") == "O'Brien"
    end
  end

  # =============================================================================
  # gather_context_from_metadata/2 - Priority Tests
  # =============================================================================

  describe "gather_context_from_metadata/2" do
    test "priority 1: uses contact_id when available" do
      user = user_fixture()
      contact = contact_fixture(name: "John Doe", email: "john@example.com")

      metadata = %{
        "contact_id" => contact.id,
        "name" => "John Doe",
        "email" => "john@example.com",
        "crm_data" => %{"company" => "Acme"}
      }

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      assert context.contact.id == contact.id
      assert context.crm_data == %{"company" => "Acme"}
      assert is_list(context.meetings)
      assert is_list(context.name_matched_meetings)
    end

    test "priority 1: falls back to email when contact_id not found" do
      user = user_fixture()
      _contact = contact_fixture(name: "John Doe", email: "john@example.com")

      metadata = %{
        "contact_id" => 999_999,
        "email" => "john@example.com",
        "crm_data" => %{"company" => "Acme"}
      }

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      # Falls back to email lookup, so no contact returned
      assert context.contact == nil
      assert context.crm_data == %{"company" => "Acme"}
    end

    test "priority 2: uses email with CRM data" do
      user = user_fixture()
      _contact = contact_fixture(name: "Jane Smith", email: "jane@example.com")

      metadata = %{
        "email" => "jane@example.com",
        "crm_data" => %{"company" => "TechCorp", "title" => "CTO"}
      }

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      assert context.contact == nil
      assert context.crm_data == %{"company" => "TechCorp", "title" => "CTO"}
    end

    test "priority 3: uses CRM data only when no email" do
      user = user_fixture()

      metadata = %{
        "crm_data" => %{"company" => "Acme", "display_name" => "Bob"},
        "name" => "Bob Wilson"
      }

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      assert context.contact == nil
      assert context.crm_data == %{"company" => "Acme", "display_name" => "Bob"}
      assert context.meetings == []
    end

    test "priority 4: uses email only" do
      user = user_fixture()
      contact = contact_fixture(name: "Alice Brown", email: "alice@example.com")

      # Create a meeting for this contact
      calendar_event = calendar_event_fixture(user_id: user.id)

      {:ok, _attendee} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: calendar_event.id,
          contact_id: contact.id,
          display_name: "Alice Brown"
        })

      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      _meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      metadata = %{"email" => "alice@example.com", "name" => "Alice Brown"}

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      assert context.contact == nil
      assert context.crm_data == nil
      assert length(context.meetings) == 1
    end

    test "fallback: returns recent meetings when no contact info" do
      user = user_fixture()

      # Create a meeting for this user
      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      _meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, %{})

      assert context.contact == nil
      assert context.crm_data == nil
      assert length(context.meetings) == 1
      assert context.name_matched_meetings == []
    end

    test "treats empty email string as no email" do
      user = user_fixture()

      metadata = %{
        "email" => "",
        "crm_data" => %{"company" => "Acme"}
      }

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      # Falls through to priority 3 (CRM data only)
      assert context.crm_data == %{"company" => "Acme"}
      assert context.meetings == []
    end

    test "handles empty crm_data map" do
      user = user_fixture()

      metadata = %{
        "email" => "test@example.com",
        "crm_data" => %{}
      }

      # Empty map is still a map, so priority 2 applies
      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      assert context.crm_data == %{}
    end

    test "ignores string contact_id (expects integer)" do
      user = user_fixture()
      contact = contact_fixture(name: "John Doe", email: "john@example.com")

      metadata = %{
        "contact_id" => "#{contact.id}",
        "email" => "john@example.com"
      }

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      # String contact_id doesn't match integer pattern, falls to email lookup
      assert context.contact == nil
    end

    test "handles nil values in metadata gracefully" do
      user = user_fixture()

      metadata = %{
        "contact_id" => nil,
        "email" => nil,
        "crm_data" => nil,
        "name" => nil
      }

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      assert context.contact == nil
      assert context.crm_data == nil
    end
  end

  # =============================================================================
  # Name-Matched Meetings
  # =============================================================================

  describe "name-matched meetings" do
    test "finds name-matched meetings when no email matches" do
      user = user_fixture()

      # Create a meeting with a participant named "Sarah"
      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      _participant = meeting_participant_fixture(meeting_id: meeting.id, name: "Sarah Chen")

      # Search for CRM contact with different email but same first name
      metadata = %{
        "crm_data" => %{"display_name" => "Sarah Johnson"},
        "email" => "sarah.johnson@newcompany.com",
        "name" => "Sarah Johnson"
      }

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      # No email match, so meetings is empty
      assert context.meetings == []
      # But name-matched meetings should find the meeting with "Sarah"
      assert length(context.name_matched_meetings) == 1
    end

    test "does not find name-matched meetings when email matches exist" do
      user = user_fixture()
      contact = contact_fixture(name: "Sarah Chen", email: "sarah@example.com")

      # Create a meeting linked to this contact
      calendar_event = calendar_event_fixture(user_id: user.id)

      {:ok, _attendee} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: calendar_event.id,
          contact_id: contact.id,
          display_name: "Sarah Chen"
        })

      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      _participant = meeting_participant_fixture(meeting_id: meeting.id, name: "Sarah Chen")

      # Create another meeting with different "Sarah" (should not be included)
      calendar_event2 = calendar_event_fixture(user_id: user.id)
      recall_bot2 = recall_bot_fixture(calendar_event_id: calendar_event2.id, user_id: user.id)

      meeting2 =
        meeting_fixture(calendar_event_id: calendar_event2.id, recall_bot_id: recall_bot2.id)

      _participant2 = meeting_participant_fixture(meeting_id: meeting2.id, name: "Sarah Other")

      metadata = %{
        "contact_id" => contact.id,
        "email" => "sarah@example.com",
        "name" => "Sarah Chen"
      }

      {:ok, context} = ContextBuilder.gather_context_from_metadata(user, metadata)

      # Email match found
      assert length(context.meetings) == 1
      # Name-matched meetings should be empty since email matches exist
      assert context.name_matched_meetings == []
    end
  end

  # =============================================================================
  # find_name_matched_meetings/3
  # =============================================================================

  describe "find_name_matched_meetings/3" do
    test "returns empty list for nil first name" do
      user = user_fixture()
      assert ContextBuilder.find_name_matched_meetings(user, nil, []) == []
    end

    test "returns empty list for empty first name" do
      user = user_fixture()
      assert ContextBuilder.find_name_matched_meetings(user, "", []) == []
    end

    test "finds meetings by participant first name" do
      user = user_fixture()

      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      _participant = meeting_participant_fixture(meeting_id: meeting.id, name: "John Smith")

      meetings = ContextBuilder.find_name_matched_meetings(user, "John", [])

      assert length(meetings) == 1
      assert hd(meetings).id == meeting.id
    end

    test "is case insensitive" do
      user = user_fixture()

      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      _participant = meeting_participant_fixture(meeting_id: meeting.id, name: "JOHN Smith")

      meetings = ContextBuilder.find_name_matched_meetings(user, "john", [])

      assert length(meetings) == 1
    end

    test "matches prefix only, not substring" do
      user = user_fixture()

      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      _participant = meeting_participant_fixture(meeting_id: meeting.id, name: "Benjamin John")

      # "John" should not match "Benjamin John" since it's not a prefix
      meetings = ContextBuilder.find_name_matched_meetings(user, "John", [])

      assert meetings == []
    end

    test "limits to 5 meetings" do
      user = user_fixture()

      # Create 7 meetings with "John"
      for i <- 1..7 do
        calendar_event = calendar_event_fixture(user_id: user.id)
        recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

        meeting =
          meeting_fixture(
            calendar_event_id: calendar_event.id,
            recall_bot_id: recall_bot.id,
            recorded_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)
          )

        meeting_participant_fixture(meeting_id: meeting.id, name: "John Doe #{i}")
      end

      meetings = ContextBuilder.find_name_matched_meetings(user, "John", [])

      assert length(meetings) == 5
    end

    test "orders by most recent first" do
      user = user_fixture()

      # Create old meeting
      old_event = calendar_event_fixture(user_id: user.id)
      old_bot = recall_bot_fixture(calendar_event_id: old_event.id, user_id: user.id)

      old_meeting =
        meeting_fixture(
          calendar_event_id: old_event.id,
          recall_bot_id: old_bot.id,
          title: "Old Meeting",
          recorded_at: DateTime.add(DateTime.utc_now(), -86400, :second)
        )

      meeting_participant_fixture(meeting_id: old_meeting.id, name: "John Old")

      # Create new meeting
      new_event = calendar_event_fixture(user_id: user.id)
      new_bot = recall_bot_fixture(calendar_event_id: new_event.id, user_id: user.id)

      new_meeting =
        meeting_fixture(
          calendar_event_id: new_event.id,
          recall_bot_id: new_bot.id,
          title: "New Meeting",
          recorded_at: DateTime.utc_now()
        )

      meeting_participant_fixture(meeting_id: new_meeting.id, name: "John New")

      meetings = ContextBuilder.find_name_matched_meetings(user, "John", [])

      assert length(meetings) == 2
      assert hd(meetings).title == "New Meeting"
    end

    test "returns distinct meetings when multiple participants match" do
      user = user_fixture()

      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      # Two participants named "John" in the same meeting
      meeting_participant_fixture(meeting_id: meeting.id, name: "John Smith")
      meeting_participant_fixture(meeting_id: meeting.id, name: "John Doe")

      meetings = ContextBuilder.find_name_matched_meetings(user, "John", [])

      # Should return 1 meeting, not 2
      assert length(meetings) == 1
    end

    test "preloads meeting_transcript, meeting_participants, and calendar_event" do
      user = user_fixture()

      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      meeting_participant_fixture(meeting_id: meeting.id, name: "John Smith")

      [found_meeting] = ContextBuilder.find_name_matched_meetings(user, "John", [])

      # Preloads should be loaded (not Ecto.Association.NotLoaded)
      assert is_list(found_meeting.meeting_participants)
      assert found_meeting.calendar_event != nil
      # meeting_transcript may be nil if not created, but should not be NotLoaded
      refute match?(%Ecto.Association.NotLoaded{}, found_meeting.meeting_transcript)
    end

    test "does not return meetings from other users" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Create meeting for user2
      calendar_event = calendar_event_fixture(user_id: user2.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user2.id)

      meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      _participant = meeting_participant_fixture(meeting_id: meeting.id, name: "John Smith")

      # user1 should not see user2's meetings
      meetings = ContextBuilder.find_name_matched_meetings(user1, "John", [])

      assert meetings == []
    end

    test "returns empty list when no meetings exist" do
      user = user_fixture()

      meetings = ContextBuilder.find_name_matched_meetings(user, "John", [])

      assert meetings == []
    end
  end

  # =============================================================================
  # find_meetings_by_email/2
  # =============================================================================

  describe "find_meetings_by_email/2" do
    test "returns empty list when email not found in contacts" do
      user = user_fixture()

      meetings = ContextBuilder.find_meetings_by_email(user, "unknown@example.com")

      assert meetings == []
    end

    test "returns meetings when email matches a contact with meetings" do
      user = user_fixture()
      contact = contact_fixture(name: "John Doe", email: "john@example.com")

      calendar_event = calendar_event_fixture(user_id: user.id)

      {:ok, _attendee} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: calendar_event.id,
          contact_id: contact.id,
          display_name: "John Doe"
        })

      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      _meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      meetings = ContextBuilder.find_meetings_by_email(user, "john@example.com")

      assert length(meetings) == 1
    end

    test "returns empty list when contact exists but has no meetings" do
      user = user_fixture()
      _contact = contact_fixture(name: "John Doe", email: "john@example.com")

      meetings = ContextBuilder.find_meetings_by_email(user, "john@example.com")

      assert meetings == []
    end

    test "returns empty list for nil email" do
      user = user_fixture()

      meetings = ContextBuilder.find_meetings_by_email(user, nil)

      assert meetings == []
    end

    test "returns empty list for non-binary email" do
      user = user_fixture()

      meetings = ContextBuilder.find_meetings_by_email(user, 123)

      assert meetings == []
    end
  end

  # =============================================================================
  # find_meetings_for_contact/2
  # =============================================================================

  describe "find_meetings_for_contact/2" do
    test "returns empty list for invalid contact" do
      user = user_fixture()

      meetings = ContextBuilder.find_meetings_for_contact(user, nil)

      assert meetings == []
    end

    test "returns empty list for contact with no meetings" do
      user = user_fixture()
      contact = contact_fixture(name: "John Doe", email: "john@example.com")

      meetings = ContextBuilder.find_meetings_for_contact(user, contact)

      assert meetings == []
    end

    test "preloads meeting_transcript, meeting_participants, and calendar_event" do
      user = user_fixture()
      contact = contact_fixture(name: "John Doe", email: "john@example.com")

      calendar_event = calendar_event_fixture(user_id: user.id)

      {:ok, _attendee} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: calendar_event.id,
          contact_id: contact.id,
          display_name: "John Doe"
        })

      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      _meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      [found_meeting] = ContextBuilder.find_meetings_for_contact(user, contact)

      assert is_list(found_meeting.meeting_participants)
      assert found_meeting.calendar_event != nil
      refute match?(%Ecto.Association.NotLoaded{}, found_meeting.meeting_transcript)
    end
  end

  # =============================================================================
  # find_recent_meetings_for_user/1
  # =============================================================================

  describe "find_recent_meetings_for_user/1" do
    test "returns empty list when user has no meetings" do
      user = user_fixture()

      meetings = ContextBuilder.find_recent_meetings_for_user(user)

      assert meetings == []
    end

    test "limits to 10 meetings" do
      user = user_fixture()

      # Create 12 meetings
      for i <- 1..12 do
        calendar_event = calendar_event_fixture(user_id: user.id)
        recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

        meeting_fixture(
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id,
          recorded_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)
        )
      end

      meetings = ContextBuilder.find_recent_meetings_for_user(user)

      assert length(meetings) == 10
    end

    test "orders by most recent first" do
      user = user_fixture()

      # Create old meeting
      old_event = calendar_event_fixture(user_id: user.id)
      old_bot = recall_bot_fixture(calendar_event_id: old_event.id, user_id: user.id)

      _old_meeting =
        meeting_fixture(
          calendar_event_id: old_event.id,
          recall_bot_id: old_bot.id,
          title: "Old Meeting",
          recorded_at: DateTime.add(DateTime.utc_now(), -86400, :second)
        )

      # Create new meeting
      new_event = calendar_event_fixture(user_id: user.id)
      new_bot = recall_bot_fixture(calendar_event_id: new_event.id, user_id: user.id)

      _new_meeting =
        meeting_fixture(
          calendar_event_id: new_event.id,
          recall_bot_id: new_bot.id,
          title: "New Meeting",
          recorded_at: DateTime.utc_now()
        )

      meetings = ContextBuilder.find_recent_meetings_for_user(user)

      assert length(meetings) == 2
      assert hd(meetings).title == "New Meeting"
    end

    test "does not return meetings from other users" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Create meeting for user2
      calendar_event = calendar_event_fixture(user_id: user2.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user2.id)

      _meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      # user1 should not see user2's meetings
      meetings = ContextBuilder.find_recent_meetings_for_user(user1)

      assert meetings == []
    end
  end

  # =============================================================================
  # gather_context/2
  # =============================================================================

  describe "gather_context/2" do
    test "returns context with contact" do
      user = user_fixture()
      contact = contact_fixture(name: "Test User", email: "test@example.com")

      {:ok, context} = ContextBuilder.gather_context(user, contact)

      assert context.contact.id == contact.id
      assert is_list(context.meetings)
      assert is_list(context.name_matched_meetings)
    end

    test "returns recent meetings when contact is nil" do
      user = user_fixture()

      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      _meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      {:ok, context} = ContextBuilder.gather_context(user, nil)

      assert context.contact == nil
      assert context.crm_data == nil
      assert length(context.meetings) == 1
      assert context.name_matched_meetings == []
    end

    test "finds name-matched meetings when contact has no email-matched meetings" do
      user = user_fixture()
      contact = contact_fixture(name: "John Doe", email: "john@example.com")

      # Create a meeting with participant "John" but not linked to contact
      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      meeting =
        meeting_fixture(calendar_event_id: calendar_event.id, recall_bot_id: recall_bot.id)

      meeting_participant_fixture(meeting_id: meeting.id, name: "John Smith")

      {:ok, context} = ContextBuilder.gather_context(user, contact)

      # No email-matched meetings
      assert context.meetings == []
      # But should find name-matched meeting
      assert length(context.name_matched_meetings) == 1
    end
  end
end
