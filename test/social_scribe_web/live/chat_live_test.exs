defmodule SocialScribeWeb.ChatLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox
  import SocialScribe.AccountsFixtures

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
end
