defmodule SocialScribeWeb.UserSettingsLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Accounts
  alias SocialScribe.Accounts.Credentials
  alias SocialScribe.Bots
  alias SocialScribe.Seeds

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns.current_user

    if connected?(socket) do
      Phoenix.PubSub.subscribe(SocialScribe.PubSub, "user:#{current_user.id}:seeding")
    end

    google_accounts = Credentials.list_user_credentials(current_user, provider: "google")
    linkedin_accounts = Credentials.list_user_credentials(current_user, provider: "linkedin")
    facebook_accounts = Credentials.list_user_credentials(current_user, provider: "facebook")
    hubspot_accounts = Credentials.list_user_credentials(current_user, provider: "hubspot")
    salesforce_accounts = Credentials.list_user_credentials(current_user, provider: "salesforce")

    user_bot_preference =
      Bots.get_user_bot_preference(current_user.id) || %Bots.UserBotPreference{}

    changeset = Bots.change_user_bot_preference(user_bot_preference)

    socket =
      socket
      |> assign(:page_title, "User Settings")
      |> assign(:google_accounts, google_accounts)
      |> assign(:linkedin_accounts, linkedin_accounts)
      |> assign(:facebook_accounts, facebook_accounts)
      |> assign(:hubspot_accounts, hubspot_accounts)
      |> assign(:salesforce_accounts, salesforce_accounts)
      |> assign(:user_bot_preference, user_bot_preference)
      |> assign(:user_bot_preference_form, to_form(changeset))
      |> assign(:seeding_in_progress, false)
      |> assign_seed_button_state()

    {:ok, socket}
  end

  defp assign_seed_button_state(socket) do
    user = socket.assigns.current_user

    show_seed_button =
      System.get_env("SHOW_SEED_BUTTON") != nil &&
        !user.has_seeded &&
        Credentials.get_user_latest_credential(user.id, "salesforce") != nil

    socket
    |> assign(:show_seed_button, show_seed_button)
    |> assign(:seeded, user.has_seeded || false)
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    case socket.assigns.live_action do
      :facebook_pages ->
        facebook_page_options =
          socket.assigns.current_user
          |> Credentials.list_linked_facebook_pages()
          |> Enum.map(&{&1.page_name, &1.id})

        socket =
          socket
          |> assign(:facebook_page_options, facebook_page_options)
          |> assign(:facebook_page_form, to_form(%{"facebook_page" => ""}))

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_user_bot_preference", %{"user_bot_preference" => params}, socket) do
    changeset =
      socket.assigns.user_bot_preference
      |> Bots.change_user_bot_preference(params)

    {:noreply, assign(socket, :user_bot_preference_form, to_form(changeset, action: :validate))}
  end

  @impl true
  def handle_event("update_user_bot_preference", %{"user_bot_preference" => params}, socket) do
    params = Map.put(params, "user_id", socket.assigns.current_user.id)

    case create_or_update_user_bot_preference(socket.assigns.user_bot_preference, params) do
      {:ok, bot_preference} ->
        {:noreply,
         socket
         |> assign(:user_bot_preference, bot_preference)
         |> put_flash(:info, "Bot preference updated successfully")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :user_bot_preference_form, to_form(changeset, action: :validate))}
    end
  end

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  @impl true
  def handle_event("select_facebook_page", %{"facebook_page" => facebook_page}, socket) do
    facebook_page_credential = Credentials.get_facebook_page_credential!(facebook_page)

    case Credentials.update_facebook_page_credential(facebook_page_credential, %{selected: true}) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Facebook page selected successfully")
          |> push_navigate(to: ~p"/dashboard/settings")

        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
    end
  end

  @impl true
  def handle_event("seed_data", _params, socket) do
    user = socket.assigns.current_user

    # Mark as seeded immediately to prevent duplicate seeding on page refresh
    Accounts.update_user_seeded(user, true)

    Task.Supervisor.start_child(SocialScribe.TaskSupervisor, fn ->
      try do
        {:ok, summary} = Seeds.run(user)

        Phoenix.PubSub.broadcast(
          SocialScribe.PubSub,
          "user:#{user.id}:seeding",
          {:seeding_complete, summary}
        )
      rescue
        e ->
          # Reset has_seeded so user can retry
          Accounts.update_user_seeded(user, false)

          Phoenix.PubSub.broadcast(
            SocialScribe.PubSub,
            "user:#{user.id}:seeding",
            {:seeding_failed, Exception.message(e)}
          )
      end
    end)

    socket =
      socket
      |> assign(:seeding_in_progress, true)
      |> assign(:show_seed_button, false)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:seeding_complete, summary}, socket) do
    message =
      "Seeded #{summary.meetings_count} meetings with #{summary.contacts_count} contacts!" <>
        if(summary.salesforce_connected, do: " (Salesforce synced)", else: "")

    socket =
      socket
      |> assign(:seeded, true)
      |> assign(:seeding_in_progress, false)
      |> put_flash(:info, message)
      |> push_navigate(to: ~p"/dashboard/meetings")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:seeding_failed, reason}, socket) do
    socket =
      socket
      |> assign(:seeding_in_progress, false)
      |> assign(:show_seed_button, true)
      |> put_flash(:error, "Seeding failed: #{inspect(reason)}")

    {:noreply, socket}
  end

  defp create_or_update_user_bot_preference(bot_preference, params) do
    case bot_preference do
      %Bots.UserBotPreference{id: nil} ->
        Bots.create_user_bot_preference(params)

      bot_preference ->
        Bots.update_user_bot_preference(bot_preference, params)
    end
  end
end
