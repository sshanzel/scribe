defmodule SocialScribeWeb.ChatLiveTest do
  use SocialScribeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox
  import SocialScribe.AccountsFixtures
  import SocialScribe.ContactsFixtures

  alias SocialScribe.Chat

  setup :verify_on_exit!

  # Helper to wait for async operations with retries
  defp eventually(view, assertion, opts \\ []) do
    retries = Keyword.get(opts, :retries, 10)
    delay = Keyword.get(opts, :delay, 50)

    Enum.reduce_while(1..retries, nil, fn attempt, _acc ->
      html = render(view)

      if assertion.(html) do
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

      # Wait for async load to complete with retry logic
      html =
        eventually(view, fn h ->
          h =~ "First Thread" and h =~ "Second Thread"
        end)

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

      # Wait for async load to complete with retry logic
      html =
        eventually(view, fn h ->
          h =~ "No conversations yet"
        end)

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

      # Wait for async message handling with retry logic
      eventually(
        view,
        fn _html -> length(Chat.list_threads(user)) == 1 end,
        retries: 20,
        delay: 25
      )

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

      # Wait for async message handling with retry logic
      # We check that exactly 1 thread exists (no new thread created)
      eventually(
        view,
        fn _html ->
          threads = Chat.list_threads(user)
          length(threads) == 1 and hd(threads).id == existing_thread.id
        end,
        retries: 20,
        delay: 25
      )

      # Verify no new threads were created
      threads = Chat.list_threads(user)
      assert length(threads) == 1
      assert hd(threads).id == existing_thread.id
    end
  end

  describe "debounce race condition handling" do
    setup %{conn: conn} do
      user = user_fixture()

      %{
        conn: log_in_user(conn, user),
        user: user
      }
    end

    test "discards stale search results when query changes during debounce", %{user: user} do
      # This test verifies that if a user types "@a", then quickly types "@ab",
      # the results from the "@a" search don't overwrite the "@ab" results.

      # Mock to track which queries were searched
      search_calls = :ets.new(:search_calls, [:set, :public])

      stub(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, query ->
        :ets.insert(search_calls, {query, true})
        # Return different results based on query to distinguish them
        if String.contains?(query, "ab") do
          {:ok, [%{id: "2", display_name: "Result for AB", email: "ab@example.com"}]}
        else
          {:ok, [%{id: "1", display_name: "Result for A", email: "a@example.com"}]}
        end
      end)

      stub(SocialScribe.SalesforceApiMock, :search_contacts, fn _credential, _query ->
        {:ok, []}
      end)

      _credential = hubspot_credential_fixture(%{user_id: user.id})

      {:ok, view, _html} =
        Phoenix.LiveViewTest.live_isolated(build_conn(), SocialScribeWeb.ChatLive,
          session: %{"user_token" => SocialScribe.Accounts.generate_user_session_token(user)}
        )

      # Type "@a" - this schedules a debounced search
      view |> render_click("message_input_change", %{"value" => "@a", "key" => "a"})

      # Immediately type "@ab" - this should cancel the previous search
      view |> render_click("message_input_change", %{"value" => "@ab", "key" => "b"})

      # Wait for results with retry logic instead of fixed sleep
      html =
        eventually(
          view,
          fn h -> h =~ "ab@example.com" or h =~ "Result for AB" end,
          retries: 15,
          delay: 50
        )

      # The final results should be for "ab", not "a"
      # If the race condition fix works, we should see "ab@example.com"
      assert html =~ "ab@example.com" or html =~ "Result for AB"

      :ets.delete(search_calls)
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

    test "escapes HTML in contact names in dropdown", %{user: user} do
      {:ok, view, _html} =
        Phoenix.LiveViewTest.live_isolated(build_conn(), SocialScribeWeb.ChatLive,
          session: %{"user_token" => SocialScribe.Accounts.generate_user_session_token(user)}
        )

      # Trigger contact search to show the XSS contact in dropdown
      view |> render_click("message_input_change", %{"value" => "@xss", "key" => "s"})

      # Wait for results to appear with retry logic
      html =
        eventually(view, fn h ->
          h =~ "xss@example.com"
        end)

      # The contact name should be escaped, not raw HTML
      refute html =~ "<script>alert('xss')</script>"
      # The email should be visible (proves contact was found)
      assert html =~ "xss@example.com"
    end

    test "contact search results escape malicious names", %{user: user} do
      # Use expect to override the stub from setup
      expect(SocialScribe.HubspotApiMock, :search_contacts, fn _credential, _query ->
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

      # Wait for results with retry logic instead of fixed sleep
      html =
        eventually(
          view,
          fn h -> h =~ "malicious@example.com" end,
          retries: 15,
          delay: 50
        )

      # The malicious HTML should be escaped, not rendered as raw HTML
      refute html =~ "<img src=x onerror="
      # The email proves the contact was found and rendered
      assert html =~ "malicious@example.com"
      # The escaped version should appear (HEEx auto-escapes angle brackets)
      assert html =~ "&lt;img" or html =~ "&amp;lt;"
    end
  end
end
