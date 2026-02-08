defmodule SocialScribeWeb.ChatLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox
  import SocialScribe.AccountsFixtures
  import SocialScribe.ContactsFixtures

  alias SocialScribe.Chat

  setup :verify_on_exit!

  describe "ChatLive rendering" do
    setup %{conn: conn} do
      # Stub mocks
      stub(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      stub(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "renders chat bubble on dashboard", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      assert html =~ "chat-container"
      assert html =~ "hero-chat-bubble-left-right"
    end

    test "chat bubble is present on meetings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings")

      assert html =~ "chat-container"
      assert html =~ "hero-chat-bubble-left-right"
    end

    test "chat bubble is present on settings page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ "chat-container"
      assert html =~ "hero-chat-bubble-left-right"
    end
  end

  describe "ChatLive history tab" do
    setup %{conn: conn} do
      stub(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      stub(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "loads and displays threads when history tab is clicked", %{user: user} do
      # Create some threads first
      {:ok, thread1} = Chat.create_thread(user)
      {:ok, _} = Chat.update_thread(thread1, %{title: "First Thread"})
      {:ok, thread2} = Chat.create_thread(user)
      {:ok, _} = Chat.update_thread(thread2, %{title: "Second Thread"})

      {:ok, view, _html} =
        Phoenix.LiveViewTest.live_isolated(build_conn(), SocialScribeWeb.ChatLive,
          session: %{"user_token" => SocialScribe.Accounts.generate_user_session_token(user)}
        )

      # Click history tab
      view |> render_click("switch_tab", %{"tab" => "history"})

      # Wait for async load to complete
      :timer.sleep(100)

      # Re-render to get updated HTML after async
      html = render(view)

      # Verify threads are displayed
      assert html =~ "First Thread"
      assert html =~ "Second Thread"
    end

    test "shows empty state when no threads exist", %{user: user} do
      {:ok, view, _html} =
        Phoenix.LiveViewTest.live_isolated(build_conn(), SocialScribeWeb.ChatLive,
          session: %{"user_token" => SocialScribe.Accounts.generate_user_session_token(user)}
        )

      # Click history tab
      view |> render_click("switch_tab", %{"tab" => "history"})

      # Wait for async load to complete
      :timer.sleep(100)

      # Re-render to get updated HTML after async
      html = render(view)

      # Verify empty state is shown
      assert html =~ "No conversations yet"
    end
  end

  describe "ChatLive send_message without existing thread" do
    setup %{conn: conn} do
      # Stub mocks
      stub(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      stub(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      # Create contact linked to user via calendar event
      %{contact: contact, user: user} =
        contact_with_event_fixture(%{name: "Test Contact", email: "test@example.com"})

      %{
        conn: log_in_user(conn, user),
        user: user,
        contact: contact
      }
    end

    test "creates thread automatically when sending message without existing thread", %{
      user: user,
      contact: contact
    } do
      # Stub ChatAIMock to return success
      expect(SocialScribe.ChatAIMock, :generate_response, fn thread, _user, _content, _metadata ->
        # Verify thread is not nil - this is the key assertion
        assert thread != nil
        assert thread.user_id == user.id
        {:ok, "Response from AI", %{"meeting_refs" => []}}
      end)

      # Verify no threads exist initially
      assert Chat.list_threads(user) == []

      # Test the ChatLive module directly using a live_isolated approach
      {:ok, view, _html} =
        Phoenix.LiveViewTest.live_isolated(build_conn(), SocialScribeWeb.ChatLive,
          session: %{"user_token" => SocialScribe.Accounts.generate_user_session_token(user)}
        )

      # Add the contact to mentions by selecting it
      view |> render_click("select_contact", %{"id" => "#{contact.id}"})

      # Send message without creating a thread first
      view
      |> render_click("send_message", %{
        "message" => "Hello @Test Contact",
        "mentions" => [%{"contact_id" => contact.id}]
      })

      # Give a moment for async message handling
      :timer.sleep(50)

      # Verify a thread was created
      threads = Chat.list_threads(user)
      assert length(threads) == 1
    end

    test "uses existing thread when one is already selected", %{
      user: user,
      contact: contact
    } do
      # Create a thread first
      {:ok, existing_thread} = Chat.create_thread(user)

      # Stub ChatAIMock to return success and verify the correct thread is used
      expect(SocialScribe.ChatAIMock, :generate_response, fn thread, _user, _content, _metadata ->
        # Verify it's the existing thread
        assert thread.id == existing_thread.id
        {:ok, "Response from AI", %{"meeting_refs" => []}}
      end)

      # Test the ChatLive module directly using a live_isolated approach
      {:ok, view, _html} =
        Phoenix.LiveViewTest.live_isolated(build_conn(), SocialScribeWeb.ChatLive,
          session: %{"user_token" => SocialScribe.Accounts.generate_user_session_token(user)}
        )

      # Select the existing thread
      view |> render_click("select_thread", %{"id" => "#{existing_thread.id}"})

      # Add the contact to mentions
      view |> render_click("select_contact", %{"id" => "#{contact.id}"})

      # Send message
      view
      |> render_click("send_message", %{
        "message" => "Hello @Test Contact",
        "mentions" => [%{"contact_id" => contact.id}]
      })

      # Give a moment for async message handling
      :timer.sleep(50)

      # Verify no new threads were created
      threads = Chat.list_threads(user)
      assert length(threads) == 1
      assert hd(threads).id == existing_thread.id
    end
  end

  describe "XSS prevention in contact display" do
    setup %{conn: conn} do
      stub(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      stub(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      # Create contact with XSS payload in name
      %{contact: contact, user: user} =
        contact_with_event_fixture(%{
          name: "<script>alert('xss')</script>",
          email: "xss@example.com"
        })

      %{
        conn: log_in_user(conn, user),
        user: user,
        contact: contact
      }
    end

    test "escapes HTML in contact names in dropdown", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard")

      # The contact name should not appear as raw HTML (would be executed)
      # Phoenix templates auto-escape, so the literal <script> should appear escaped
      refute html =~ "<script>alert('xss')</script>"
    end

    test "contact search results escape malicious names", %{user: user} do
      # Mock HubSpot to return a contact with XSS payload
      stub(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
        {:ok,
         [
           %{
             id: "xss123",
             display_name: "<img src=x onerror=alert('xss')>",
             email: "malicious@example.com",
             company: "Evil Corp"
           }
         ]}
      end)

      _credential = hubspot_credential_fixture(%{user_id: user.id})

      {:ok, view, _html} =
        Phoenix.LiveViewTest.live_isolated(build_conn(), SocialScribeWeb.ChatLive,
          session: %{"user_token" => SocialScribe.Accounts.generate_user_session_token(user)}
        )

      # Trigger contact search via message_input_change with @ mention
      view |> render_click("message_input_change", %{"value" => "@test", "key" => "t"})

      # Wait for debounced search to complete
      :timer.sleep(350)

      html = render(view)

      # The malicious HTML should be escaped, not rendered as raw HTML
      refute html =~ "<img src=x onerror="
      # The escaped version should appear (HEEx auto-escapes)
      assert html =~ "&lt;img src=x" or html =~ "malicious@example.com"
    end
  end
end
