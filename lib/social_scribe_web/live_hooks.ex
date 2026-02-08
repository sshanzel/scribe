defmodule SocialScribeWeb.LiveHooks do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias SocialScribe.Accounts.Credentials
  alias SocialScribe.Seeds

  def on_mount(:assign_current_path, _params, _session, socket) do
    env_enabled = System.get_env("SHOW_SEED_BUTTON") != nil
    user = socket.assigns[:current_user]
    seeded = user && Map.get(user, :has_seeded, false)

    # Only show seed button if env is set AND user has Salesforce connected
    has_salesforce =
      user && Credentials.get_user_latest_credential(user.id, "salesforce") != nil

    show_seed_button = env_enabled and has_salesforce

    socket =
      socket
      |> assign(:show_seed_button, show_seed_button)
      |> assign(:seeded, seeded)
      |> attach_hook(:assign_current_path, :handle_params, &assign_current_path/3)
      |> attach_hook(:handle_seed_event, :handle_event, &handle_seed_event/3)

    {:cont, socket}
  end

  defp assign_current_path(_params, uri, socket) do
    uri = URI.parse(uri)

    {:cont, assign(socket, :current_path, uri.path)}
  end

  defp handle_seed_event("seed_data", _params, socket) do
    user = socket.assigns.current_user

    try do
      {:ok, summary} = Seeds.run(user)

      # Mark user as seeded
      SocialScribe.Accounts.update_user_seeded(user, true)

      message =
        "Seeded #{summary.meetings_count} meetings with #{summary.contacts_count} contacts!" <>
          if(summary.salesforce_connected, do: " (Salesforce synced)", else: "")

      socket =
        socket
        |> assign(:seeded, true)
        |> Phoenix.LiveView.put_flash(:info, message)

      {:halt, socket}
    rescue
      e ->
        {:halt,
         Phoenix.LiveView.put_flash(socket, :error, "Seeding failed: #{Exception.message(e)}")}
    end
  end

  defp handle_seed_event(_event, _params, socket) do
    {:cont, socket}
  end
end
