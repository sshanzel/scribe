defmodule SocialScribe.CalendarSyncronizerTest do
  use SocialScribe.DataCase, async: true

  import Mox
  import SocialScribe.AccountsFixtures

  # The context containing the sync logic
  alias SocialScribe.CalendarSyncronizer
  alias SocialScribe.Calendar.CalendarEvent
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
        %{"email" => "john@example.com", "displayName" => "John Doe", "responseStatus" => "accepted"},
        %{"email" => "jane@example.com", "displayName" => "Jane Smith", "responseStatus" => "tentative"}
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

      assert Repo.aggregate(CalendarEvent, :count, :id) == 2

      zoom_event = Repo.get_by!(CalendarEvent, google_event_id: "zoom-event-123")
      assert zoom_event.summary == "Zoom Meeting"
      assert zoom_event.user_id == user.id
      assert zoom_event.user_credential_id == credential.id

      meet_event = Repo.get_by!(CalendarEvent, google_event_id: "meet-event-456")
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

      assert Repo.aggregate(CalendarEvent, :count, :id) == 1
      assert Repo.get_by!(CalendarEvent, google_event_id: "zoom-event-123")
    end

    test "extracts attendees from Google Calendar events" do
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

      # Event with attendees
      zoom_event = Repo.get_by!(CalendarEvent, google_event_id: "zoom-event-123")
      assert length(zoom_event.attendees) == 2

      [first_attendee, second_attendee] = zoom_event.attendees
      assert first_attendee["email"] == "john@example.com"
      assert first_attendee["name"] == "John Doe"
      assert first_attendee["response_status"] == "accepted"

      assert second_attendee["email"] == "jane@example.com"
      assert second_attendee["name"] == "Jane Smith"
      assert second_attendee["response_status"] == "tentative"

      # Event without attendees
      meet_event = Repo.get_by!(CalendarEvent, google_event_id: "meet-event-456")
      assert meet_event.attendees == []
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
          %{"email" => "valid@example.com", "displayName" => "Valid User", "responseStatus" => "accepted"},
          %{"displayName" => "No Email User", "responseStatus" => "accepted"},
          %{"email" => nil, "displayName" => "Nil Email User", "responseStatus" => "accepted"}
        ]
      }

      expect(GoogleApiMock, :list_events, fn _token, _start_time, _end_time, _calendar_id ->
        {:ok, %{"items" => [event_with_partial_attendees]}}
      end)

      assert {:ok, :sync_complete} = CalendarSyncronizer.sync_events_for_user(user)

      event = Repo.get_by!(CalendarEvent, google_event_id: "partial-attendees-event")
      assert length(event.attendees) == 1
      assert Enum.at(event.attendees, 0)["email"] == "valid@example.com"
    end
  end
end
