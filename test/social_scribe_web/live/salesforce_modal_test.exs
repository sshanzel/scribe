defmodule SocialScribeWeb.SalesforceModalTest do
  @moduledoc """
  Tests for Salesforce modal functionality.
  Tests the flow: search → select contact → generate suggestions → apply updates.
  """
  use SocialScribeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures

  alias SocialScribe.CRM.Salesforce.ApiBehaviour

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

  describe "Salesforce Modal with mocked API" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "renders modal when navigating to salesforce route", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "#salesforce-modal-wrapper")
      assert has_element?(view, "h2", "Update in Salesforce")
    end

    test "displays contact search input", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "input[placeholder*='Search']")
      assert has_element?(view, "input[phx-keyup='contact_search']")
    end

    test "shows contact search initially without suggestions form", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "input[phx-keyup='contact_search']")
      refute has_element?(view, "form[phx-submit='apply_updates']")
    end

    test "pre-fills search with participant name and triggers search on open", %{conn: conn} do
      user = user_fixture()
      _credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_participant(user, "Marcus Johnson")

      # Mock the search that will be triggered automatically
      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, query ->
        assert query == "Marcus Johnson"

        {:ok,
         [
           %{
             id: "003MARCUS",
             firstname: "Marcus",
             lastname: "Johnson",
             email: "marcus@example.com",
             phone: "555-5678"
           }
         ]}
      end)

      {:ok, view, html} =
        live(log_in_user(conn, user), ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Search input should be pre-filled with participant name
      assert html =~ "Marcus Johnson"

      # Wait for search results to appear
      html = wait_for(view, fn h -> h =~ "marcus@example.com" end)
      assert html =~ "marcus@example.com"
    end

    test "search_contacts returns mocked results", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "003ABC123",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: "555-1234"
        },
        %{
          id: "003ABC456",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@example.com",
          phone: "555-5678"
        }
      ]

      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, query ->
        assert query == "John"
        {:ok, contacts}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      html = wait_for(view, fn h -> h =~ "john@example.com" end)

      assert html =~ "John Doe"
      assert html =~ "john@example.com"
      assert html =~ "Jane Smith"
    end

    test "search_contacts handles API error gracefully", %{conn: conn, meeting: meeting} do
      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, _query ->
        {:error, {:api_error, 500, "Internal Server Error"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Test"})

      html = wait_for(view, fn h -> h =~ "Failed to search" end)

      assert html =~ "Failed to search"
    end

    test "selecting contact triggers suggestion generation", %{conn: conn, meeting: meeting} do
      contact = %{
        id: "003XYZ789",
        firstname: "John",
        lastname: "Doe",
        email: "john@example.com",
        phone: "555-0000"
      }

      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, _query ->
        {:ok, [contact]}
      end)

      expect(SocialScribe.AIContentGeneratorMock, :generate_crm_suggestions, fn :salesforce,
                                                                                _meeting ->
        {:ok,
         [
           %{field: "phone", value: "555-9999", context: "Mentioned new phone number"}
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      wait_for(view, fn h -> h =~ "john@example.com" end)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='003XYZ789']")
      |> render_click()

      html = wait_for(view, fn h -> h =~ "555-9999" end)

      assert html =~ "555-9999"
      assert html =~ "salesforce-modal-wrapper"
    end

    test "contact dropdown shows search results", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "003AAA111",
          firstname: "Alice",
          lastname: "Anderson",
          email: "alice@test.com",
          phone: "111-1111"
        }
      ]

      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, _query ->
        {:ok, contacts}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Alice"})

      html = wait_for(view, fn h -> h =~ "alice@test.com" end)

      assert html =~ "Alice Anderson"
      assert html =~ "alice@test.com"
    end

    test "applying updates calls Salesforce API", %{conn: conn, meeting: meeting} do
      contact = %{
        id: "003BBB222",
        firstname: "Bob",
        lastname: "Builder",
        email: "bob@example.com",
        phone: "000-0000"
      }

      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, _query ->
        {:ok, [contact]}
      end)

      expect(SocialScribe.AIContentGeneratorMock, :generate_crm_suggestions, fn :salesforce,
                                                                                _meeting ->
        {:ok,
         [
           %{field: "phone", value: "999-8888", context: "Bob mentioned new number"}
         ]}
      end)

      expect(SocialScribe.SalesforceApiMock, :update_contact, fn _credential, contact_id, updates ->
        assert contact_id == "003BBB222"
        assert updates["phone"] == "999-8888"
        {:ok, Map.merge(contact, %{phone: "999-8888"})}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Bob"})

      wait_for(view, fn h -> h =~ "bob@example.com" end)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='003BBB222']")
      |> render_click()

      wait_for(view, fn h -> h =~ "999-8888" end)

      view
      |> element("form[phx-submit='apply_updates']")
      |> render_submit(%{
        "apply" => %{"phone" => "on"},
        "values" => %{"phone" => "999-8888"}
      })

      :timer.sleep(100)
    end

    test "modal can be closed by navigating back", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      assert has_element?(view, "#salesforce-modal-wrapper")

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute has_element?(view, "#salesforce-modal-wrapper")
    end
  end

  describe "Salesforce Modal - without credential" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "does not show Salesforce section when no credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "Salesforce Integration"
      refute html =~ "Update Salesforce Contact"
    end

    test "does not render modal when accessing salesforce route without credential", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      refute html =~ "salesforce-modal-wrapper"
    end
  end

  describe "Salesforce API behavior delegation" do
    setup do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      %{credential: credential}
    end

    test "search_contacts delegates to implementation", %{credential: credential} do
      expect(SocialScribe.SalesforceApiMock, :search_contacts, fn _cred, query ->
        assert query == "test query"
        {:ok, [%{id: "003TEST", firstname: "Test", lastname: "User", email: "test@example.com"}]}
      end)

      result = ApiBehaviour.search_contacts(credential, "test query")
      assert {:ok, [%{id: "003TEST"}]} = result
    end

    test "get_contact delegates to implementation", %{credential: credential} do
      expect(SocialScribe.SalesforceApiMock, :get_contact, fn _cred, contact_id ->
        assert contact_id == "003ABC123"
        {:ok, %{id: "003ABC123", firstname: "John", lastname: "Doe"}}
      end)

      result = ApiBehaviour.get_contact(credential, "003ABC123")
      assert {:ok, %{id: "003ABC123"}} = result
    end

    test "update_contact delegates to implementation", %{credential: credential} do
      expect(SocialScribe.SalesforceApiMock, :update_contact, fn _cred, contact_id, updates ->
        assert contact_id == "003DEF456"
        assert updates == %{"Phone" => "555-1234"}
        {:ok, %{id: "003DEF456", phone: "555-1234"}}
      end)

      result = ApiBehaviour.update_contact(credential, "003DEF456", %{"Phone" => "555-1234"})
      assert {:ok, %{id: "003DEF456"}} = result
    end

    test "apply_updates delegates to implementation", %{credential: credential} do
      updates_list = [
        %{field: "Phone", new_value: "555-9999", apply: true},
        %{field: "Title", new_value: "CEO", apply: false}
      ]

      expect(SocialScribe.SalesforceApiMock, :apply_updates, fn _cred, contact_id, updates ->
        assert contact_id == "003GHI789"
        assert length(updates) == 2
        {:ok, %{id: "003GHI789", phone: "555-9999"}}
      end)

      result = ApiBehaviour.apply_updates(credential, "003GHI789", updates_list)
      assert {:ok, %{id: "003GHI789"}} = result
    end
  end

  # Helper to create meeting with transcript
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

  # Meeting fixture with a specific participant name for pre-fill testing
  defp meeting_fixture_with_participant(user, participant_name) do
    meeting = meeting_fixture(%{})

    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)
    {:ok, _} = SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{"data" => []}
    })

    meeting_participant_fixture(%{
      meeting_id: meeting.id,
      name: participant_name,
      is_host: false
    })

    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
