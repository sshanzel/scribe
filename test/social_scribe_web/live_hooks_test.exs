defmodule SocialScribeWeb.LiveHooksTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias SocialScribeWeb.LiveHooks

  describe "on_mount(:assign_timezone)" do
    test "assigns timezone from connect params when connected", %{conn: conn} do
      # Create a test LiveView that uses the hook
      {:ok, view, _html} =
        conn
        |> put_connect_params(%{"timezone" => "America/New_York"})
        |> live_isolated(__MODULE__.TestLiveView, session: %{})

      # The timezone should be assigned
      assert render(view) =~ "timezone:America/New_York"
    end

    test "defaults to UTC when timezone not in connect params", %{conn: conn} do
      {:ok, view, _html} =
        conn
        |> put_connect_params(%{})
        |> live_isolated(__MODULE__.TestLiveView, session: %{})

      assert render(view) =~ "timezone:UTC"
    end

    test "defaults to UTC when not connected (static render)" do
      # When not connected, get_connect_params returns nil
      # The hook should default to UTC
      socket =
        %Phoenix.LiveView.Socket{}
        |> Phoenix.Component.assign(:__changed__, %{})

      {:cont, socket} = LiveHooks.on_mount(:assign_timezone, %{}, %{}, socket)

      assert socket.assigns.timezone == "UTC"
    end
  end

  # Test LiveView module for isolated testing
  defmodule TestLiveView do
    use Phoenix.LiveView

    on_mount {SocialScribeWeb.LiveHooks, :assign_timezone}

    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    def render(assigns) do
      ~H"""
      <div>timezone:{@timezone}</div>
      """
    end
  end
end
