defmodule SocialScribe.CalendarSyncronizerTest do
  # async: false because module attributes use hardcoded emails that conflict with other tests
  use SocialScribe.DataCase, async: false

  import Mox
  import SocialScribe.AccountsFixtures

  # The context containing the sync logic
  alias SocialScribe.CalendarSyncronizer
  alias SocialScribe.Calendar.CalendarEvent
  alias SocialScribe.Contacts
  alias SocialScribe.TokenRefresherMock
  alias SocialScribe.GoogleCalendarApiMock, as: GoogleApiMock

  # Mock data for a Google Calendar API response
  @mock_google_events [
    %{
      "id" => "zoom-event-123",
      "summary" => "Zoom Meeting",
      "location" => "https://us05web.zoom.us/j/12345",
      "start" => %{"dateTime" => "2025-05-25T10:00:00-03:00"},
      "end" => %{"dateTime" => "2025-05-25T11:00:00-03:00"},
      "status" => "confirmed",
      "htmlLink" => "https://calendar.google.com/calendar/event?eid=zoom-event-123",
      "attendees" => [
        %{
          "email" => "john@example.com",
          "displayName" => "John Doe",
          "responseStatus" => "accepted"
        },
        %{
          "email" => "jane@example.com",
          "displayName" => "Jane Smith",
          "responseStatus" => "tentative"
        }
      ]
    },
    %{
      "id" => "meet-event-456",
      "summary" => "Google Meet Call",
      "hangoutLink" => "https://meet.google.com/abc-def-ghi",
      "start" => %{"dateTime" => "2025-05-26T14:00:00-03:00"},
      "end" => %{"dateTime" => "2025-05-26T14:30:00-03:00"},
      "status" => "confirmed",
      "htmlLink" => "https://calendar.google.com/calendar/event?eid=meet-event-456"
    },
    %{
      "id" => "no-link-event-789",
      "summary" => "Lunch Break",
      "start" => %{"dateTime" => "2025-05-26T12:00:00-03:00"},
      "end" => %{"dateTime" => "2025-05-26T13:00:00-03:00"},
      "status" => "confirmed",
      "htmlLink" => nil
    }
  ]

  describe "sync_events_for_user/1" do
    setup do
      stub_with(GoogleApiMock, SocialScribe.GoogleCalendar)
      stub_with(TokenRefresherMock, SocialScribe.TokenRefresher)
      :ok
    end

    test "fetches and syncs new events with meeting links to the database" do
      user = user_fixture()

      credential =
        user_credential_fixture(%{
          provider: "google",
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      expect(GoogleApiMock, :list_events, fn _token, _start_time, _end_time, calendar_id ->
        assert calendar_id == "primary"
        {:ok, %{"items" => @mock_google_events}}
      end)

      assert {:ok, :sync_complete} = CalendarSyncronizer.sync_events_for_user(user)

      # Only events with meeting links should be synced
      events = Repo.all(from e in CalendarEvent, where: e.user_id == ^user.id)
      assert length(events) == 2

      zoom_event =
        Repo.get_by!(CalendarEvent, google_event_id: "zoom-event-123", user_id: user.id)

      assert zoom_event.summary == "Zoom Meeting"
      assert zoom_event.user_id == user.id
      assert zoom_event.user_credential_id == credential.id

      meet_event =
        Repo.get_by!(CalendarEvent, google_event_id: "meet-event-456", user_id: user.id)

      assert meet_event.summary == "Google Meet Call"

      assert Repo.get_by(CalendarEvent, google_event_id: "no-link-event-789") == nil
    end

    test "refreshes token if expired and then syncs events" do
      user = user_fixture()

      credential =
        user_credential_fixture(%{
          provider: "google",
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), -100, :second)
        })

      new_token_data = %{"access_token" => "new-refreshed-token", "expires_in" => 3600}
      refresh_token = credential.refresh_token

      expect(TokenRefresherMock, :refresh_token, fn ^refresh_token ->
        {:ok, new_token_data}
      end)

      expect(GoogleApiMock, :list_events, fn "new-refreshed-token", _, _, _ ->
        {:ok, %{"items" => [@mock_google_events |> Enum.at(0)]}}
      end)

      assert {:ok, :sync_complete} = CalendarSyncronizer.sync_events_for_user(user)

      events = Repo.all(from e in CalendarEvent, where: e.user_id == ^user.id)
      assert length(events) == 1
      assert Repo.get_by!(CalendarEvent, google_event_id: "zoom-event-123", user_id: user.id)
    end

    test "creates attendee records from Google Calendar events" do
      user = user_fixture()

      _credential =
        user_credential_fixture(%{
          provider: "google",
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      expect(GoogleApiMock, :list_events, fn _token, _start_time, _end_time, _calendar_id ->
        {:ok, %{"items" => @mock_google_events}}
      end)

      assert {:ok, :sync_complete} = CalendarSyncronizer.sync_events_for_user(user)

      # Event with attendees - should have 2 contacts visible to user
      contacts = Contacts.list_contacts(user)
      assert length(contacts) == 2

      emails = Enum.map(contacts, & &1.email)
      assert "john@example.com" in emails
      assert "jane@example.com" in emails
    end

    test "filters out attendees without email" do
      user = user_fixture()

      _credential =
        user_credential_fixture(%{
          provider: "google",
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      event_with_partial_attendees = %{
        "id" => "partial-attendees-event",
        "summary" => "Partial Attendees Meeting",
        "location" => "https://us05web.zoom.us/j/12345",
        "start" => %{"dateTime" => "2025-05-25T10:00:00-03:00"},
        "end" => %{"dateTime" => "2025-05-25T11:00:00-03:00"},
        "status" => "confirmed",
        "htmlLink" => "https://calendar.google.com/calendar/event?eid=partial",
        "attendees" => [
          %{
            "email" => "valid@example.com",
            "displayName" => "Valid User",
            "responseStatus" => "accepted"
          },
          %{"displayName" => "No Email User", "responseStatus" => "accepted"},
          %{"email" => nil, "displayName" => "Nil Email User", "responseStatus" => "accepted"}
        ]
      }

      expect(GoogleApiMock, :list_events, fn _token, _start_time, _end_time, _calendar_id ->
        {:ok, %{"items" => [event_with_partial_attendees]}}
      end)

      assert {:ok, :sync_complete} = CalendarSyncronizer.sync_events_for_user(user)

      # Only one valid contact should be created
      contacts = Contacts.list_contacts(user)
      assert length(contacts) == 1
      assert hd(contacts).email == "valid@example.com"
    end
  end
end
