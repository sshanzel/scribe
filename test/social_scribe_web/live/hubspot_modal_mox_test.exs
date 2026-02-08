defmodule SocialScribeWeb.HubspotModalMoxTest do
  @moduledoc """
  Tests for HubSpot modal functionality using Mox.
  Tests the flow: search → select contact → generate suggestions → apply updates.
  """
  use SocialScribeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures

  alias SocialScribe.CRM.HubSpot.ApiBehaviour

  setup :verify_on_exit!

  # Helper to wait for async operations
  defp wait_for(view, condition, opts \\ []) do
    retries = Keyword.get(opts, :retries, 20)
    delay = Keyword.get(opts, :delay, 50)

    Enum.reduce_while(1..retries, nil, fn attempt, _acc ->
      html = render(view)

      if condition.(html) do
        {:halt, html}
      else
        if attempt < retries do
          :timer.sleep(delay)
          {:cont, nil}
        else
          {:halt, html}
        end
      end
    end)
  end

  describe "HubSpot Modal with mocked API" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot_credential = hubspot_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        hubspot_credential: hubspot_credential
      }
    end

    test "search_contacts returns mocked results", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "contact-1",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: "555-1234"
        },
        %{
          id: "contact-2",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@example.com",
          phone: "555-5678"
        }
      ]

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, query ->
        assert query == "John"
        {:ok, contacts}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      # Trigger search
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      # Wait for search results
      html = wait_for(view, fn h -> h =~ "john@example.com" end)

      assert html =~ "John Doe"
      assert html =~ "john@example.com"
      assert html =~ "Jane Smith"
    end

    test "search_contacts handles API error gracefully", %{conn: conn, meeting: meeting} do
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:error, {:api_error, 500, "Internal Server Error"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Test"})

      # Wait for error message
      html = wait_for(view, fn h -> h =~ "Failed to search" end)

      assert html =~ "Failed to search"
    end

    test "selecting contact triggers suggestion generation", %{conn: conn, meeting: meeting} do
      contact = %{
        id: "contact-123",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: "555-0000"
      }

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:ok, [contact]}
      end)

      expect(SocialScribe.AIContentGeneratorMock, :generate_crm_suggestions, fn :hubspot,
                                                                                _meeting ->
        {:ok,
         [
           %{field: "phone", value: "555-9999", context: "Mentioned new phone number"}
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      # Search for contact
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      # Wait for search results
      wait_for(view, fn h -> h =~ "john@example.com" end)

      # Select the contact
      view
      |> element("button[phx-click='select_contact'][phx-value-id='contact-123']")
      |> render_click()

      # Wait for suggestions
      html = wait_for(view, fn h -> h =~ "555-9999" end)

      # Modal should show suggestions
      assert html =~ "555-9999"
      assert html =~ "hubspot-modal-wrapper"
    end

    test "contact dropdown shows search results", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "c1",
          firstname: "Alice",
          lastname: "Anderson",
          email: "alice@test.com",
          phone: "111-1111"
        }
      ]

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:ok, contacts}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Alice"})

      # Wait for search results
      html = wait_for(view, fn h -> h =~ "alice@test.com" end)

      assert html =~ "Alice Anderson"
      assert html =~ "alice@test.com"
    end

    test "applying updates calls HubSpot API", %{conn: conn, meeting: meeting} do
      contact = %{
        id: "contact-456",
        firstname: "Bob",
        lastname: "Builder",
        email: "bob@example.com",
        phone: "000-0000"
      }

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:ok, [contact]}
      end)

      expect(SocialScribe.AIContentGeneratorMock, :generate_crm_suggestions, fn :hubspot,
                                                                                _meeting ->
        {:ok,
         [
           %{field: "phone", value: "999-8888", context: "Bob mentioned new number"}
         ]}
      end)

      expect(SocialScribe.HubspotApiMock, :update_contact, fn _credential, contact_id, updates ->
        assert contact_id == "contact-456"
        assert updates["phone"] == "999-8888"
        {:ok, Map.merge(contact, %{phone: "999-8888"})}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      # Search for contact
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Bob"})

      # Wait for search results
      wait_for(view, fn h -> h =~ "bob@example.com" end)

      # Select contact
      view
      |> element("button[phx-click='select_contact'][phx-value-id='contact-456']")
      |> render_click()

      # Wait for suggestions
      wait_for(view, fn h -> h =~ "999-8888" end)

      # Submit the update form
      view
      |> element("form[phx-submit='apply_updates']")
      |> render_submit(%{
        "apply" => %{"phone" => "on"},
        "values" => %{"phone" => "999-8888"}
      })

      # Wait for update to complete
      :timer.sleep(100)
    end
  end

  describe "HubSpot Modal - without credential" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "does not show HubSpot button when no credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "Update HubSpot"
    end
  end

  describe "HubSpot API behavior delegation" do
    setup do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})
      %{credential: credential}
    end

    test "search_contacts delegates to implementation", %{credential: credential} do
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _cred, query ->
        assert query == "test query"
        {:ok, [%{id: "1", firstname: "Test", lastname: "User", email: "test@example.com"}]}
      end)

      result = ApiBehaviour.search_contacts(credential, "test query")
      assert {:ok, [%{id: "1"}]} = result
    end

    test "get_contact delegates to implementation", %{credential: credential} do
      expect(SocialScribe.HubspotApiMock, :get_contact, fn _cred, contact_id ->
        assert contact_id == "contact-123"
        {:ok, %{id: "contact-123", firstname: "John", lastname: "Doe"}}
      end)

      result = ApiBehaviour.get_contact(credential, "contact-123")
      assert {:ok, %{id: "contact-123"}} = result
    end

    test "update_contact delegates to implementation", %{credential: credential} do
      expect(SocialScribe.HubspotApiMock, :update_contact, fn _cred, contact_id, updates ->
        assert contact_id == "contact-456"
        assert updates == %{"phone" => "555-1234"}
        {:ok, %{id: "contact-456", phone: "555-1234"}}
      end)

      result = ApiBehaviour.update_contact(credential, "contact-456", %{"phone" => "555-1234"})
      assert {:ok, %{id: "contact-456"}} = result
    end

    test "apply_updates delegates to implementation", %{credential: credential} do
      updates_list = [
        %{field: "phone", new_value: "555-9999", apply: true},
        %{field: "title", new_value: "CEO", apply: false}
      ]

      expect(SocialScribe.HubspotApiMock, :apply_updates, fn _cred, contact_id, updates ->
        assert contact_id == "contact-789"
        assert length(updates) == 2
        {:ok, %{id: "contact-789", phone: "555-9999"}}
      end)

      result = ApiBehaviour.apply_updates(credential, "contact-789", updates_list)
      assert {:ok, %{id: "contact-789"}} = result
    end
  end

  # Meeting fixture with transcript
  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)
    {:ok, _} = SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "speaker" => "John Doe",
            "words" => [
              %{"text" => "Hello,", "start_timestamp" => 0.0, "end_timestamp" => 0.5},
              %{"text" => "my", "start_timestamp" => 0.5, "end_timestamp" => 0.7},
              %{"text" => "phone", "start_timestamp" => 0.7, "end_timestamp" => 1.0},
              %{"text" => "is", "start_timestamp" => 1.0, "end_timestamp" => 1.2},
              %{"text" => "555-1234", "start_timestamp" => 1.2, "end_timestamp" => 1.8}
            ]
          }
        ]
      }
    })

    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
