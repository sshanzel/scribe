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
      |> assign(:error_message, nil)
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
              {if @current_thread, do: @current_thread.title || "New Chat", else: "Chat"}
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
                    {raw(render_message_content(message))}
                  </div>
                  <div class="text-xs mt-1 opacity-70">
                    {Calendar.strftime(message.inserted_at, "%H:%M")}
                  </div>
                </div>
              </div>

              <div :if={@loading} class="flex justify-start">
                <div class="bg-gray-100 rounded-lg px-4 py-2 text-gray-500">
                  <span class="animate-pulse">Thinking...</span>
                </div>
              </div>

              <div :if={@error_message} class="flex justify-start">
                <div class="bg-red-50 border border-red-200 rounded-lg px-4 py-3 text-red-700 max-w-[85%]">
                  <div class="flex items-start gap-2">
                    <.icon name="hero-exclamation-circle" class="size-5 flex-shrink-0 mt-0.5" />
                    <div>
                      <p class="text-sm">{@error_message}</p>
                      <button
                        phx-click="dismiss_error"
                        class="text-xs text-red-600 hover:text-red-800 mt-1 underline"
                      >
                        Dismiss
                      </button>
                    </div>
                  </div>
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
                        {String.first(contact.name)}
                      </span>
                      <div>
                        <div class="text-sm font-medium text-gray-900">{contact.name}</div>
                        <div class="text-xs text-gray-500">{contact.email}</div>
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
                    {thread.title || "New Chat"}
                  </div>
                  <div class="text-sm text-gray-500">
                    {Calendar.strftime(thread.updated_at, "%b %d, %Y")}
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
      |> assign(:error_message, nil)
      |> push_event("clear_input", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("dismiss_error", _params, socket) do
    {:noreply, assign(socket, :error_message, nil)}
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

      # Show loading state, clear input and any previous error
      socket =
        socket
        |> assign(:loading, true)
        |> assign(:error_message, nil)
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
    handle_event(
      "send_message",
      %{"message" => content, "mentions" => socket.assigns.mentions},
      socket
    )
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
          |> assign(:error_message, nil)

        {:error, {_error_type, message}} when is_binary(message) ->
          # Display friendly error message in the chat area
          socket
          |> assign(:loading, false)
          |> assign(:error_message, message)

        {:error, reason} ->
          # Fallback for unexpected error formats
          socket
          |> assign(:loading, false)
          |> assign(:error_message, "Something went wrong: #{inspect(reason)}")
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

  defp render_message_content(%{content: content, metadata: metadata, role: "user"}) do
    # For user messages: escape first, then render mentions with avatars
    mentions = metadata["mentions"] || []

    content
    |> escape_html()
    |> render_markdown_simple()
    |> render_mentions(mentions)
  end

  defp render_message_content(%{content: content, metadata: metadata, role: _role}) do
    # For assistant messages: escape first, then render meeting links and markdown
    meeting_refs = metadata["meeting_refs"] || []

    content
    |> escape_html()
    |> render_meeting_links(meeting_refs)
    |> render_markdown_simple()
  end

  defp render_mentions(content, []), do: content

  defp render_mentions(content, mentions) do
    Enum.reduce(mentions, content, fn mention, acc ->
      name = mention["name"] || ""
      first_name = name |> String.split() |> List.first() || name
      encoded_name = URI.encode(name)

      # The @ was already escaped, so match the escaped version
      pattern = "@#{escape_html(name)}"

      avatar_html =
        ~s(<span class="inline-flex items-center gap-1 bg-indigo-100 text-indigo-800 rounded-full px-2 py-0.5 text-sm font-medium"><img src="https://ui-avatars.com/api/?name=#{encoded_name}&size=20&background=4f46e5&color=fff&bold=true" class="w-5 h-5 rounded-full" alt="#{first_name}"/>#{first_name}</span>)

      String.replace(acc, pattern, avatar_html)
    end)
  end

  defp render_meeting_links(content, []), do: content

  defp render_meeting_links(content, _meeting_refs) do
    # Convert [Meeting: title (date)](meeting:123) to clickable links
    # Note: brackets and parens are not escaped by our escape_html
    Regex.replace(
      ~r/\[Meeting:\s*(.+?)\]\(meeting:(\d+)\)/,
      content,
      ~s(<a href="/dashboard/meetings/\\2" class="text-indigo-600 hover:text-indigo-800 underline">\\1</a>)
    )
  end

  defp render_markdown_simple(content) do
    # Simple markdown rendering - content is already escaped
    content
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
    |> String.replace(~r/\n/, "<br/>")
  end

  defp escape_html(content) do
    content
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
