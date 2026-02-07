defmodule SocialScribe.ChatAITest do
  use SocialScribe.DataCase, async: true

  import Mox
  import SocialScribe.AccountsFixtures
  import SocialScribe.ContactsFixtures
  import SocialScribe.ChatFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.BotsFixtures

  alias SocialScribe.ChatAI
  alias SocialScribe.Contacts

  setup :verify_on_exit!

  # =============================================================================
  # Contact Resolution Tests
  # =============================================================================

  describe "resolve_contact_from_metadata/1" do
    test "resolves contact from metadata with string keys" do
      contact = contact_fixture()

      metadata = %{"mentions" => [%{"contact_id" => contact.id, "name" => contact.name}]}

      assert {:ok, resolved} = ChatAI.resolve_contact_from_metadata(metadata)
      assert resolved.id == contact.id
    end

    test "resolves contact from metadata with atom keys" do
      contact = contact_fixture()

      metadata = %{mentions: [%{contact_id: contact.id, name: contact.name}]}

      assert {:ok, resolved} = ChatAI.resolve_contact_from_metadata(metadata)
      assert resolved.id == contact.id
    end

    test "returns nil contact when no mentions in metadata" do
      assert {:ok, nil} = ChatAI.resolve_contact_from_metadata(%{})
    end

    test "returns nil contact when mentions is empty" do
      assert {:ok, nil} = ChatAI.resolve_contact_from_metadata(%{"mentions" => []})
    end

    test "returns error when contact not found" do
      metadata = %{"mentions" => [%{"contact_id" => 999_999}]}

      assert {:error, :contact_not_found} = ChatAI.resolve_contact_from_metadata(metadata)
    end
  end

  # =============================================================================
  # Meeting Context Tests
  # =============================================================================

  describe "find_meetings_for_contact/2" do
    test "finds meetings where contact is linked via calendar event attendee" do
      user = user_fixture()

      # Create a contact
      {:ok, contact} = Contacts.create_contact(%{name: "John Doe", email: unique_email("john")})

      # Create a calendar event for the user
      calendar_event = calendar_event_fixture(user_id: user.id)

      # Link the contact to the calendar event
      {:ok, _attendee} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: calendar_event.id,
          contact_id: contact.id,
          display_name: "John Doe"
        })

      # Create a meeting for that calendar event
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      _meeting =
        meeting_fixture(
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id,
          title: "Meeting with John"
        )

      meetings = ChatAI.find_meetings_for_contact(user, contact)

      assert length(meetings) == 1
      assert hd(meetings).title == "Meeting with John"
    end

    test "returns empty list when no meetings with contact" do
      user = user_fixture()
      contact = contact_fixture(email: "unknown@example.com")

      meetings = ChatAI.find_meetings_for_contact(user, contact)

      assert meetings == []
    end

    test "limits to 10 most recent meetings" do
      user = user_fixture()
      {:ok, contact} = Contacts.create_contact(%{name: "John Doe", email: unique_email("john")})

      # Create 12 meetings
      for i <- 1..12 do
        calendar_event = calendar_event_fixture(user_id: user.id)

        {:ok, _attendee} =
          Contacts.create_calendar_event_attendee(%{
            calendar_event_id: calendar_event.id,
            contact_id: contact.id,
            display_name: "John Doe"
          })

        recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

        meeting_fixture(
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id,
          title: "Meeting #{i}",
          recorded_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)
        )
      end

      meetings = ChatAI.find_meetings_for_contact(user, contact)

      assert length(meetings) == 10
    end

    test "orders meetings by most recent first" do
      user = user_fixture()
      {:ok, contact} = Contacts.create_contact(%{name: "John Doe", email: unique_email("john")})

      # Create older meeting
      old_event = calendar_event_fixture(user_id: user.id)

      {:ok, _} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: old_event.id,
          contact_id: contact.id,
          display_name: "John Doe"
        })

      old_bot = recall_bot_fixture(calendar_event_id: old_event.id, user_id: user.id)

      _old_meeting =
        meeting_fixture(
          calendar_event_id: old_event.id,
          recall_bot_id: old_bot.id,
          title: "Old Meeting",
          recorded_at: DateTime.add(DateTime.utc_now(), -86400, :second)
        )

      # Create newer meeting
      new_event = calendar_event_fixture(user_id: user.id)

      {:ok, _} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: new_event.id,
          contact_id: contact.id,
          display_name: "John Doe"
        })

      new_bot = recall_bot_fixture(calendar_event_id: new_event.id, user_id: user.id)

      _new_meeting =
        meeting_fixture(
          calendar_event_id: new_event.id,
          recall_bot_id: new_bot.id,
          title: "New Meeting",
          recorded_at: DateTime.utc_now()
        )

      meetings = ChatAI.find_meetings_for_contact(user, contact)

      assert length(meetings) == 2
      assert hd(meetings).title == "New Meeting"
    end

    test "does not return meetings from other users" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, contact} = Contacts.create_contact(%{name: "John Doe", email: unique_email("john")})

      # Create meeting for user2 with the same contact
      calendar_event = calendar_event_fixture(user_id: user2.id)

      {:ok, _} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: calendar_event.id,
          contact_id: contact.id,
          display_name: "John Doe"
        })

      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user2.id)

      _meeting =
        meeting_fixture(
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id
        )

      # user1 should not see user2's meetings
      meetings = ChatAI.find_meetings_for_contact(user1, contact)

      assert meetings == []
    end

    test "both users see only their own meetings with shared contact" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, contact} = Contacts.create_contact(%{name: "John Doe", email: unique_email("john")})

      # User1's meeting with John
      event1 = calendar_event_fixture(user_id: user1.id)

      {:ok, _} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: event1.id,
          contact_id: contact.id,
          display_name: "John Doe"
        })

      bot1 = recall_bot_fixture(calendar_event_id: event1.id, user_id: user1.id)

      _meeting1 =
        meeting_fixture(
          calendar_event_id: event1.id,
          recall_bot_id: bot1.id,
          title: "User1's Meeting with John"
        )

      # User2's meeting with the same contact
      event2 = calendar_event_fixture(user_id: user2.id)

      {:ok, _} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: event2.id,
          contact_id: contact.id,
          display_name: "John Doe"
        })

      bot2 = recall_bot_fixture(calendar_event_id: event2.id, user_id: user2.id)

      _meeting2 =
        meeting_fixture(
          calendar_event_id: event2.id,
          recall_bot_id: bot2.id,
          title: "User2's Meeting with John"
        )

      # Each user should only see their own meeting
      user1_meetings = ChatAI.find_meetings_for_contact(user1, contact)
      user2_meetings = ChatAI.find_meetings_for_contact(user2, contact)

      assert length(user1_meetings) == 1
      assert hd(user1_meetings).title == "User1's Meeting with John"

      assert length(user2_meetings) == 1
      assert hd(user2_meetings).title == "User2's Meeting with John"
    end
  end

  # =============================================================================
  # Recent Meetings Tests (No Contact)
  # =============================================================================

  describe "find_recent_meetings_for_user/1" do
    test "finds recent meetings for user without contact filter" do
      user = user_fixture()

      # Create a calendar event and meeting for the user
      calendar_event = calendar_event_fixture(user_id: user.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

      _meeting =
        meeting_fixture(
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id,
          title: "User's Meeting"
        )

      meetings = ChatAI.find_recent_meetings_for_user(user)

      assert length(meetings) == 1
      assert hd(meetings).title == "User's Meeting"
    end

    test "limits to 10 most recent meetings" do
      user = user_fixture()

      # Create 12 meetings
      for i <- 1..12 do
        calendar_event = calendar_event_fixture(user_id: user.id)
        recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user.id)

        meeting_fixture(
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id,
          title: "Meeting #{i}",
          recorded_at: DateTime.add(DateTime.utc_now(), -i * 3600, :second)
        )
      end

      meetings = ChatAI.find_recent_meetings_for_user(user)

      assert length(meetings) == 10
    end

    test "does not return meetings from other users" do
      user1 = user_fixture()
      user2 = user_fixture()

      # Create meeting for user2
      calendar_event = calendar_event_fixture(user_id: user2.id)
      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user2.id)

      _meeting =
        meeting_fixture(
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id
        )

      # user1 should not see user2's meetings
      meetings = ChatAI.find_recent_meetings_for_user(user1)

      assert meetings == []
    end
  end

  # =============================================================================
  # Thread Title Generation Tests
  # =============================================================================

  describe "generate_thread_title/1" do
    test "returns 'New Chat' for empty thread" do
      user = user_fixture()
      thread = chat_thread_fixture(user: user)

      assert {:ok, "New Chat"} = ChatAI.generate_thread_title(thread)
    end

    test "returns truncated content when no API key" do
      user = user_fixture()
      thread = chat_thread_fixture(user: user)

      # Create a user message
      _msg =
        chat_message_fixture(
          thread: thread,
          role: "user",
          content: "What did John say about the Q1 budget proposal?"
        )

      # Should return truncated content since no API key configured in test
      assert {:ok, title} = ChatAI.generate_thread_title(thread)
      assert is_binary(title)
    end
  end
end
