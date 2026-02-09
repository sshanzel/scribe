defmodule SocialScribeWeb.LiveHooks do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, get_connect_params: 1, connected?: 1]

  def on_mount(:assign_current_path, _params, _session, socket) do
    socket =
      socket
      |> attach_hook(:assign_current_path, :handle_params, &assign_current_path/3)

    {:cont, socket}
  end

  @doc """
  Assigns the user's timezone from LiveSocket connect params.
  Falls back to "UTC" if not available.
  """
  def on_mount(:assign_timezone, _params, _session, socket) do
    timezone =
      if connected?(socket) do
        get_connect_params(socket)["timezone"] || "UTC"
      else
        "UTC"
      end

    {:cont, assign(socket, :timezone, timezone)}
  end

  defp assign_current_path(_params, uri, socket) do
    uri = URI.parse(uri)

    {:cont, assign(socket, :current_path, uri.path)}
  end
end
