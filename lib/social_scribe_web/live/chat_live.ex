defmodule SocialScribeWeb.ChatLive do
  @moduledoc """
  LiveView for the floating chat interface.
  This is embedded in the dashboard layout.
  """
  use SocialScribeWeb, :live_view

  on_mount {SocialScribeWeb.UserAuth, :mount_current_user}

  alias SocialScribe.Chat
  alias SocialScribe.Contacts
  alias SocialScribe.ChatAIApi

  @impl true
  def mount(_params, _session, socket) do
    # No layout for embedded LiveView to avoid duplicate flash groups
    socket =
      socket
      |> assign(:open, false)
      |> assign(:threads, [])
      |> assign(:current_thread, nil)
      |> assign(:messages, [])
      |> assign(:loading, false)
      |> assign(:message_input, "")
      |> assign(:contact_results, [])
      |> assign(:mentions, [])
      |> assign(:show_mention_dropdown, false)
      |> assign(:mention_search_start, nil)

    # Load threads if user is logged in
    socket =
      if socket.assigns[:current_user] do
        assign(socket, :threads, Chat.list_threads(socket.assigns.current_user))
      else
        socket
      end

    # No layout for embedded LiveView
    {:ok, socket, layout: false}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="chat-container" class="fixed bottom-4 right-4 z-50">
      <!-- Chat Bubble -->
      <button
        :if={!@open}
        phx-click="toggle_chat"
        class="w-14 h-14 bg-indigo-600 rounded-full shadow-lg flex items-center justify-center hover:bg-indigo-700 transition-colors"
        aria-label="Open chat"
      >
        <.icon name="hero-chat-bubble-left-right" class="size-6 text-white" />
      </button>

      <!-- Chat Panel -->
      <div
        :if={@open}
        class="w-96 h-[32rem] bg-white rounded-lg shadow-xl flex flex-col border border-gray-200"
      >
        <!-- Header -->
        <div class="flex items-center justify-between px-4 py-3 border-b border-gray-200 bg-indigo-600 rounded-t-lg">
          <div class="flex items-center gap-2">
            <button
              :if={@current_thread}
              phx-click="back_to_threads"
              class="text-white hover:text-gray-200"
            >
              <.icon name="hero-arrow-left" class="size-5" />
            </button>
            <h3 class="font-semibold text-white">
              <%= if @current_thread, do: @current_thread.title || "New Chat", else: "Chat" %>
            </h3>
          </div>
          <button phx-click="toggle_chat" class="text-white hover:text-gray-200">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <!-- Content Area -->
        <div class="flex-1 overflow-hidden flex flex-col">
          <%= if @current_thread do %>
            <!-- Messages View -->
            <div
              id="messages-container"
              class="flex-1 overflow-y-auto p-4 space-y-4"
              phx-hook="ScrollToBottom"
            >
              <div :for={message <- @messages} class={message_class(message.role)}>
                <div class={message_bubble_class(message.role)}>
                  <div class="prose prose-sm max-w-none">
                    <%= raw(render_markdown(message.content)) %>
                  </div>
                  <div class="text-xs mt-1 opacity-70">
                    <%= Calendar.strftime(message.inserted_at, "%H:%M") %>
                  </div>
                </div>
              </div>

              <div :if={@loading} class="flex justify-start">
                <div class="bg-gray-100 rounded-lg px-4 py-2 text-gray-500">
                  <span class="animate-pulse">Thinking...</span>
                </div>
              </div>
            </div>

            <!-- Message Input -->
            <div class="p-4 border-t border-gray-200">
              <div class="flex gap-2">
                <div class="flex-1 relative">
                  <!-- Contenteditable Input with Mention Support -->
                  <div
                    id="mention-input"
                    phx-hook="MentionInput"
                    phx-update="ignore"
                    contenteditable="true"
                    data-placeholder="Type @ to mention a contact..."
                    class="min-h-[38px] max-h-[120px] overflow-y-auto w-full rounded-lg border border-gray-300 focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 focus:outline-none text-sm px-3 py-2 empty:before:content-[attr(data-placeholder)] empty:before:text-gray-400"
                  ></div>

                  <!-- Contact Mention Dropdown -->
                  <div
                    :if={@show_mention_dropdown && length(@contact_results) > 0}
                    class="absolute bottom-full left-0 w-full bg-white border border-gray-200 rounded-lg shadow-lg mb-1 max-h-40 overflow-y-auto z-10"
                  >
                    <button
                      :for={contact <- @contact_results}
                      type="button"
                      phx-click="select_contact"
                      phx-value-id={contact.id}
                      class="w-full px-4 py-2 text-left hover:bg-gray-50 flex items-center gap-2"
                    >
                      <span class="w-6 h-6 bg-indigo-100 rounded-full flex items-center justify-center text-xs text-indigo-600 font-medium">
                        <%= String.first(contact.name) %>
                      </span>
                      <div>
                        <div class="text-sm font-medium text-gray-900"><%= contact.name %></div>
                        <div class="text-xs text-gray-500"><%= contact.email %></div>
                      </div>
                    </button>
                  </div>
                </div>

                <button
                  type="button"
                  id="chat-submit-btn"
                  phx-click={JS.dispatch("chat:submit", to: "#mention-input")}
                  disabled={@mentions == [] || @message_input == ""}
                  class="px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed self-end"
                >
                  <.icon name="hero-paper-airplane" class="size-5" />
                </button>
              </div>

              <p :if={@mentions == []} class="text-xs text-gray-400 mt-2">
                Type @ to mention a contact and ask questions about your meetings
              </p>
            </div>
          <% else %>
            <!-- Thread List -->
            <div class="flex-1 overflow-y-auto">
              <!-- New Thread Button -->
              <button
                phx-click="new_thread"
                class="w-full p-4 text-left hover:bg-gray-50 border-b border-gray-100 flex items-center gap-2 text-indigo-600"
              >
                <.icon name="hero-plus-circle" class="size-5" />
                <span>New Chat</span>
              </button>

              <!-- Thread Items -->
              <div :for={thread <- @threads} class="border-b border-gray-100">
                <button
                  phx-click="select_thread"
                  phx-value-id={thread.id}
                  class="w-full p-4 text-left hover:bg-gray-50"
                >
                  <div class="font-medium text-gray-900 truncate">
                    <%= thread.title || "New Chat" %>
                  </div>
                  <div class="text-sm text-gray-500">
                    <%= Calendar.strftime(thread.updated_at, "%b %d, %Y") %>
                  </div>
                </button>
              </div>

              <div :if={@threads == []} class="p-4 text-center text-gray-500">
                No conversations yet. Start a new chat!
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # =============================================================================
  # Event Handlers
  # =============================================================================

  @impl true
  def handle_event("toggle_chat", _params, socket) do
    socket =
      if !socket.assigns.open do
        # Load threads when opening
        threads = Chat.list_threads(socket.assigns.current_user)
        assign(socket, threads: threads, open: true)
      else
        assign(socket, open: false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("new_thread", _params, socket) do
    {:ok, thread} = Chat.create_thread(socket.assigns.current_user)

    socket =
      socket
      |> assign(:current_thread, thread)
      |> assign(:messages, [])
      |> assign(:threads, [thread | socket.assigns.threads])

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_thread", %{"id" => id}, socket) do
    thread_id = String.to_integer(id)
    {:ok, thread} = Chat.get_thread_for_user(socket.assigns.current_user, thread_id)
    messages = Chat.list_messages(thread)

    socket =
      socket
      |> assign(:current_thread, thread)
      |> assign(:messages, messages)

    {:noreply, socket}
  end

  @impl true
  def handle_event("back_to_threads", _params, socket) do
    threads = Chat.list_threads(socket.assigns.current_user)

    socket =
      socket
      |> assign(:current_thread, nil)
      |> assign(:messages, [])
      |> assign(:threads, threads)
      |> assign(:mentions, [])
      |> assign(:message_input, "")
      |> assign(:show_mention_dropdown, false)
      |> push_event("clear_input", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("message_input_change", params, socket) do
    # phx-keyup sends value in params, but key varies based on event type
    value = params["value"] || ""

    socket =
      socket
      |> assign(:message_input, value)
      |> maybe_search_contacts(value)

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_contact", %{"id" => id}, socket) do
    contact_id = String.to_integer(id)
    contact = Contacts.get_contact!(contact_id)

    # Add contact to mentions list
    mentions = socket.assigns.mentions ++ [contact]

    socket =
      socket
      |> assign(:mentions, mentions)
      |> assign(:show_mention_dropdown, false)
      |> assign(:contact_results, [])
      |> push_event("insert_mention", %{id: contact.id, name: contact.name})

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_mention_dropdown", _params, socket) do
    {:noreply, assign(socket, show_mention_dropdown: false, contact_results: [])}
  end

  @impl true
  def handle_event("send_message", %{"message" => content, "mentions" => mentions_data}, socket) do
    content = String.trim(content)

    if content == "" || mentions_data == [] do
      {:noreply, socket}
    else
      thread = socket.assigns.current_thread

      # Build metadata from mentions
      metadata = %{
        "mentions" =>
          Enum.map(socket.assigns.mentions, fn contact ->
            %{
              "contact_id" => contact.id,
              "name" => contact.name,
              "email" => contact.email
            }
          end)
      }

      # Show loading state and clear input
      socket =
        socket
        |> assign(:loading, true)
        |> assign(:message_input, "")
        |> assign(:mentions, [])
        |> push_event("clear_input", %{})

      # Generate response asynchronously
      send(self(), {:generate_response, thread, content, metadata})

      {:noreply, socket}
    end
  end

  # Fallback for old send_message format (form submission)
  @impl true
  def handle_event("send_message", %{"message" => content}, socket) do
    handle_event("send_message", %{"message" => content, "mentions" => socket.assigns.mentions}, socket)
  end

  @impl true
  def handle_info({:generate_response, thread, content, metadata}, socket) do
    socket =
      case ChatAIApi.generate_response(thread, socket.assigns.current_user, content, metadata) do
        {:ok, _response, _response_metadata} ->
          # Reload messages
          messages = Chat.list_messages(thread)
          {:ok, updated_thread} = Chat.get_thread_for_user(socket.assigns.current_user, thread.id)

          socket
          |> assign(:messages, messages)
          |> assign(:current_thread, updated_thread)
          |> assign(:loading, false)

        {:error, reason} ->
          socket
          |> assign(:loading, false)
          |> put_flash(:error, "Failed to generate response: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp maybe_search_contacts(%{assigns: %{current_user: nil}} = socket, _value) do
    socket
    |> assign(:show_mention_dropdown, false)
    |> assign(:contact_results, [])
  end

  defp maybe_search_contacts(socket, value) do
    # Check if there's an @ mention at the end
    case Regex.run(~r/@(\S*)$/, value) do
      [_, query] when byte_size(query) >= 1 ->
        results = Contacts.search_contacts(socket.assigns.current_user, query)

        socket
        |> assign(:show_mention_dropdown, true)
        |> assign(:contact_results, results)

      [_, ""] ->
        # Just @ with no query yet - show first 5 contacts
        results = Contacts.list_contacts(socket.assigns.current_user) |> Enum.take(5)

        socket
        |> assign(:show_mention_dropdown, true)
        |> assign(:contact_results, results)

      nil ->
        socket
        |> assign(:show_mention_dropdown, false)
        |> assign(:contact_results, [])
    end
  end

  defp message_class("user"), do: "flex justify-end"
  defp message_class(_), do: "flex justify-start"

  defp message_bubble_class("user"),
    do: "bg-indigo-600 text-white rounded-lg px-4 py-2 max-w-[80%]"

  defp message_bubble_class(_),
    do: "bg-gray-100 text-gray-900 rounded-lg px-4 py-2 max-w-[80%]"

  defp render_markdown(content) do
    # Simple markdown rendering - just escape HTML and convert basic markdown
    content
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
    |> String.replace(~r/\n/, "<br/>")
  end
end
