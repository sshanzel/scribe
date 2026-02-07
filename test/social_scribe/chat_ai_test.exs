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

  setup :verify_on_exit!

  # =============================================================================
  # Contact Resolution Tests
  # =============================================================================

  describe "resolve_contact_from_metadata/1" do
    test "resolves contact from metadata with string keys" do
      user = user_fixture()
      contact = contact_fixture(user: user)

      metadata = %{"mentions" => [%{"contact_id" => contact.id, "name" => contact.name}]}

      assert {:ok, resolved} = ChatAI.resolve_contact_from_metadata(metadata)
      assert resolved.id == contact.id
    end

    test "resolves contact from metadata with atom keys" do
      user = user_fixture()
      contact = contact_fixture(user: user)

      metadata = %{mentions: [%{contact_id: contact.id, name: contact.name}]}

      assert {:ok, resolved} = ChatAI.resolve_contact_from_metadata(metadata)
      assert resolved.id == contact.id
    end

    test "returns error when no mentions in metadata" do
      assert {:error, :no_contact_tagged} = ChatAI.resolve_contact_from_metadata(%{})
    end

    test "returns error when mentions is empty" do
      assert {:error, :no_contact_tagged} =
               ChatAI.resolve_contact_from_metadata(%{"mentions" => []})
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
    test "finds meetings where contact email is in attendees" do
      user = user_fixture()
      contact = contact_fixture(user: user, email: "john@example.com")

      # Create a calendar event with attendees that include the contact
      calendar_event =
        calendar_event_fixture(
          user_id: user.id,
          attendees: [%{"email" => "john@example.com", "name" => "John Doe"}]
        )

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
      contact = contact_fixture(user: user, email: "unknown@example.com")

      meetings = ChatAI.find_meetings_for_contact(user, contact)

      assert meetings == []
    end

    test "limits to 10 most recent meetings" do
      user = user_fixture()
      contact = contact_fixture(user: user, email: "john@example.com")

      # Create 12 meetings
      for i <- 1..12 do
        calendar_event =
          calendar_event_fixture(
            user_id: user.id,
            attendees: [%{"email" => "john@example.com", "name" => "John"}]
          )

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
      contact = contact_fixture(user: user, email: "john@example.com")

      # Create older meeting
      old_event =
        calendar_event_fixture(
          user_id: user.id,
          attendees: [%{"email" => "john@example.com"}]
        )

      old_bot = recall_bot_fixture(calendar_event_id: old_event.id, user_id: user.id)

      _old_meeting =
        meeting_fixture(
          calendar_event_id: old_event.id,
          recall_bot_id: old_bot.id,
          title: "Old Meeting",
          recorded_at: DateTime.add(DateTime.utc_now(), -86400, :second)
        )

      # Create newer meeting
      new_event =
        calendar_event_fixture(
          user_id: user.id,
          attendees: [%{"email" => "john@example.com"}]
        )

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
      contact = contact_fixture(user: user1, email: "john@example.com")

      # Create meeting for user2
      calendar_event =
        calendar_event_fixture(
          user_id: user2.id,
          attendees: [%{"email" => "john@example.com"}]
        )

      recall_bot = recall_bot_fixture(calendar_event_id: calendar_event.id, user_id: user2.id)

      _meeting =
        meeting_fixture(
          calendar_event_id: calendar_event.id,
          recall_bot_id: recall_bot.id
        )

      meetings = ChatAI.find_meetings_for_contact(user1, contact)

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
