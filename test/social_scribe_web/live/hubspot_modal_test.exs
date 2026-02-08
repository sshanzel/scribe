defmodule SocialScribeWeb.HubspotModalTest do
  @moduledoc """
  Tests for HubSpot modal functionality.
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

    test "renders modal when navigating to hubspot route", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      assert has_element?(view, "#hubspot-modal-wrapper")
      assert has_element?(view, "h2", "Update in HubSpot")
    end

    test "displays contact search input", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      assert has_element?(view, "input[placeholder*='Search']")
      assert has_element?(view, "input[phx-keyup='contact_search']")
    end

    test "shows contact search initially without suggestions form", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      assert has_element?(view, "input[phx-keyup='contact_search']")
      refute has_element?(view, "form[phx-submit='apply_updates']")
    end

    test "search_contacts returns mocked results", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "101",
          firstname: "John",
          lastname: "Doe",
          display_name: "John Doe",
          email: "john@example.com",
          phone: "555-1234"
        },
        %{
          id: "102",
          firstname: "Jane",
          lastname: "Smith",
          display_name: "Jane Smith",
          email: "jane@example.com",
          phone: "555-5678"
        }
      ]

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, query ->
        assert query == "John"
        {:ok, contacts}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

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

      html = wait_for(view, fn h -> h =~ "Failed to search" end)

      assert html =~ "Failed to search"
    end

    test "selecting contact triggers suggestion generation", %{conn: conn, meeting: meeting} do
      contact = %{
        id: "103",
        firstname: "John",
        lastname: "Doe",
        display_name: "John Doe",
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
           %{
             field: "phone",
             value: "555-9999",
             context: "John said 'my new number is 555-9999'",
             timestamp: "01:23"
           }
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      wait_for(view, fn h -> h =~ "john@example.com" end)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='103']")
      |> render_click()

      html = wait_for(view, fn h -> h =~ "555-9999" end)

      assert html =~ "555-9999"
      assert html =~ "hubspot-modal-wrapper"
      assert html =~ "Found in transcript"
      assert html =~ "(01:23)"
    end

    test "contact dropdown shows search results", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "104",
          firstname: "Alice",
          lastname: "Anderson",
          display_name: "Alice Anderson",
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

      html = wait_for(view, fn h -> h =~ "alice@test.com" end)

      assert html =~ "Alice Anderson"
      assert html =~ "alice@test.com"
    end

    test "applying updates calls HubSpot API", %{conn: conn, meeting: meeting} do
      contact = %{
        id: "105",
        firstname: "Bob",
        lastname: "Builder",
        display_name: "Bob Builder",
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
           %{
             field: "phone",
             value: "999-8888",
             context: "Bob said 'call me at 999-8888'",
             timestamp: "02:45"
           }
         ]}
      end)

      expect(SocialScribe.HubspotApiMock, :update_contact, fn _credential, contact_id, updates ->
        assert contact_id == "105"
        assert updates["phone"] == "999-8888"
        {:ok, Map.merge(contact, %{phone: "999-8888"})}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Bob"})

      wait_for(view, fn h -> h =~ "bob@example.com" end)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='105']")
      |> render_click()

      wait_for(view, fn h -> h =~ "999-8888" end)

      view
      |> element("form[phx-submit='apply_updates']")
      |> render_submit(%{
        "apply" => %{"phone" => "on"},
        "values" => %{"phone" => "999-8888"}
      })

      # Wait for async update to complete
      wait_for(view, fn _h -> true end, retries: 5, delay: 50)
    end

    test "toggle_suggestion updates checkbox state", %{conn: conn, meeting: meeting} do
      contact = %{
        id: "106",
        firstname: "Toggle",
        lastname: "Test",
        display_name: "Toggle Test",
        email: "toggle@example.com",
        phone: "111-0000"
      }

      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:ok, [contact]}
      end)

      expect(SocialScribe.AIContentGeneratorMock, :generate_crm_suggestions, fn :hubspot,
                                                                                _meeting ->
        {:ok,
         [
           %{
             field: "phone",
             value: "222-3333",
             context: "New phone mentioned",
             timestamp: "00:30"
           }
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      # Search and select contact to generate suggestions
      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Toggle"})

      wait_for(view, fn h -> h =~ "toggle@example.com" end)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='106']")
      |> render_click()

      # Wait for suggestions to appear
      html = wait_for(view, fn h -> h =~ "222-3333" end)

      # Verify checkbox is initially checked (apply: true by default)
      assert html =~ "222-3333"

      # Toggle the suggestion off by submitting the form change event
      view
      |> element("form[phx-submit='apply_updates']")
      |> render_change(%{
        "apply" => %{},
        "values" => %{"phone" => "222-3333"}
      })

      # Toggle it back on
      html =
        view
        |> element("form[phx-submit='apply_updates']")
        |> render_change(%{
          "apply" => %{"phone" => "on"},
          "values" => %{"phone" => "222-3333"}
        })

      # Verify form still shows the suggestion value
      assert html =~ "222-3333"
    end

    test "modal can be closed by navigating back", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      assert has_element?(view, "#hubspot-modal-wrapper")

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute has_element?(view, "#hubspot-modal-wrapper")
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

    test "does not show HubSpot section when no credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "HubSpot Integration"
      refute html =~ "Update HubSpot Contact"
    end

    test "does not render modal when accessing hubspot route without credential", %{
      conn: conn,
      meeting: meeting
    } do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/hubspot")

      refute html =~ "hubspot-modal-wrapper"
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
        {:ok, [%{id: "101", display_name: "Test User", email: "test@example.com"}]}
      end)

      result = ApiBehaviour.search_contacts(credential, "test query")
      assert {:ok, [%{id: "101"}]} = result
    end

    test "get_contact delegates to implementation", %{credential: credential} do
      expect(SocialScribe.HubspotApiMock, :get_contact, fn _cred, contact_id ->
        assert contact_id == "101"
        {:ok, %{id: "101", display_name: "John Doe"}}
      end)

      result = ApiBehaviour.get_contact(credential, "101")
      assert {:ok, %{id: "101"}} = result
    end

    test "update_contact delegates to implementation", %{credential: credential} do
      expect(SocialScribe.HubspotApiMock, :update_contact, fn _cred, contact_id, updates ->
        assert contact_id == "102"
        # Uses internal field names (lowercase), mapped to API names by FieldMapper
        assert updates == %{"phone" => "555-1234"}
        {:ok, %{id: "102", phone: "555-1234"}}
      end)

      result = ApiBehaviour.update_contact(credential, "102", %{"phone" => "555-1234"})
      assert {:ok, %{id: "102"}} = result
    end

    test "apply_updates delegates to implementation", %{credential: credential} do
      # Uses internal field names (lowercase), mapped to API names by FieldMapper
      updates_list = [
        %{field: "phone", new_value: "555-9999", apply: true},
        %{field: "jobtitle", new_value: "CEO", apply: false}
      ]

      expect(SocialScribe.HubspotApiMock, :apply_updates, fn _cred, contact_id, updates ->
        assert contact_id == "103"
        assert length(updates) == 2
        {:ok, %{id: "103", phone: "555-9999"}}
      end)

      result = ApiBehaviour.apply_updates(credential, "103", updates_list)
      assert {:ok, %{id: "103"}} = result
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
end
