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
      |> assign(:active_tab, :chat)

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
        class="w-14 h-14 bg-slate-700 rounded-full shadow-lg flex items-center justify-center hover:bg-slate-800 transition-colors"
        aria-label="Open chat"
      >
        <.icon name="hero-chat-bubble-left-right" class="size-6 text-white" />
      </button>

      <.drawer id="chat-drawer" open={@open} on_close="toggle_chat">
        <:header>
          <h3 class="font-semibold text-slate-800">Ask Anything</h3>
        </:header>
        <:body>
          <!-- Tab Bar -->
          <div class="flex items-center justify-between px-4 py-2">
            <div class="flex gap-1">
              <button
                phx-click="switch_tab"
                phx-value-tab="chat"
                class={"px-3 py-1 text-sm font-medium rounded-full transition-colors " <>
                  if(@active_tab == :chat,
                    do: "bg-slate-700 text-white",
                    else: "text-slate-600 hover:bg-slate-100"
                  )}
              >
                Chat
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="history"
                class={"px-3 py-1 text-sm font-medium rounded-full transition-colors " <>
                  if(@active_tab == :history,
                    do: "bg-slate-700 text-white",
                    else: "text-slate-600 hover:bg-slate-100"
                  )}
              >
                History
              </button>
            </div>
            <button
              :if={@messages != []}
              phx-click="new_thread"
              class="p-1.5 text-slate-500 hover:text-slate-700 hover:bg-slate-100 rounded-full transition-colors"
              title="New chat"
            >
              <.icon name="hero-plus" class="size-5" />
            </button>
          </div>
          
    <!-- Content Area -->
          <div class="flex-1 overflow-hidden flex flex-col">
            <%= if @active_tab == :chat do %>
              <!-- Messages View -->
              <div
                id="messages-container"
                class="flex-1 overflow-y-auto p-4 space-y-4"
                phx-hook="ScrollToBottom"
              >
                <%= if @current_thread do %>
                  <!-- Timestamp for first message -->
                  <div :if={@messages != []} class="text-center text-xs text-slate-400 pb-2">
                    {format_thread_timestamp(List.first(@messages).inserted_at)}
                  </div>

                  <div :for={message <- @messages} class={message_class(message.role)}>
                    <div class={message_bubble_class(message.role)}>
                      <div class="prose prose-sm max-w-none prose-slate">
                        {raw(render_message_content(message))}
                      </div>
                      <div class="text-xs mt-1 opacity-60">
                        {Calendar.strftime(message.inserted_at, "%H:%M")}
                      </div>
                    </div>
                  </div>

                  <div :if={@loading} class="flex justify-start">
                    <div class="bg-slate-100 rounded-lg px-4 py-2 text-slate-500">
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
                <% else %>
                  <!-- Empty state when no thread selected -->
                  <div class="flex-1 flex flex-col items-center justify-center text-slate-400 py-8">
                    <.icon name="hero-chat-bubble-left-right" class="size-12 mb-3" />
                    <p class="text-sm">Start a new conversation</p>
                    <p class="text-xs mt-1">Type @ to mention a contact</p>
                  </div>
                <% end %>
              </div>
              
              <!-- Message Input Container -->
              <div class="p-3">
                <div class="rounded-lg border border-slate-200 bg-white">
                  <!-- Row 1: Add context button -->
                  <div class="px-3 pt-2">
                    <button
                      type="button"
                      class="inline-flex items-center gap-0.5 text-xs text-slate-400 hover:text-slate-600 hover:bg-slate-50 border border-slate-200 rounded px-1.5 py-0.5 transition-colors"
                    >
                      <.icon name="hero-at-symbol" class="size-3" />
                      <span>Add context</span>
                    </button>
                  </div>
                  
    <!-- Row 2: Input field (plain) -->
                  <div class="relative">
                    <div
                      id="mention-input"
                      phx-hook="MentionInput"
                      phx-update="ignore"
                      contenteditable="true"
                      data-placeholder="Type @ to mention a contact..."
                      class="min-h-[60px] max-h-[120px] overflow-y-auto w-full focus:outline-none text-sm px-3 py-2 empty:before:content-[attr(data-placeholder)] empty:before:text-slate-400"
                    ></div>
                    
    <!-- Contact Mention Dropdown -->
                    <div
                      :if={@show_mention_dropdown && length(@contact_results) > 0}
                      class="absolute bottom-full left-0 w-full bg-white border border-slate-200 rounded-lg shadow-lg mb-1 max-h-40 overflow-y-auto z-10"
                    >
                      <button
                        :for={contact <- @contact_results}
                        type="button"
                        phx-click="select_contact"
                        phx-value-id={contact.id}
                        class="w-full px-3 py-2 text-left hover:bg-slate-50 flex items-center gap-2"
                      >
                        <img
                          src={"https://ui-avatars.com/api/?name=#{URI.encode(contact.name)}&size=24&background=475569&color=fff"}
                          class="w-6 h-6 rounded-full"
                          alt={contact.name}
                        />
                        <div>
                          <div class="text-sm font-medium text-slate-800">{contact.name}</div>
                          <div class="text-xs text-slate-500">{contact.email}</div>
                        </div>
                      </button>
                    </div>
                  </div>
                  
                  <!-- Row 3: Sources + Submit button -->
                  <div class="px-3 py-2 flex items-center justify-between">
                    <div class="flex items-center gap-2">
                      <span class="text-xs text-slate-400">Sources</span>
                      <div class="flex -space-x-2">
                        <!-- Jump AI icon -->
                        <div
                          class="w-5 h-5 rounded-full bg-slate-700 flex items-center justify-center ring-2 ring-white z-40"
                          title="Jump AI"
                        >
                          <.icon name="hero-sparkles" class="size-3 text-white" />
                        </div>
                        <!-- Gmail icon -->
                        <div
                          class="w-5 h-5 rounded-full bg-red-500 flex items-center justify-center ring-2 ring-white z-30"
                          title="Gmail"
                        >
                          <.icon name="hero-envelope" class="size-3 text-white" />
                        </div>
                        <!-- HubSpot icon -->
                        <div
                          class="w-5 h-5 rounded-full bg-orange-500 flex items-center justify-center ring-2 ring-white z-20"
                          title="HubSpot"
                        >
                          <.icon name="hero-building-office" class="size-3 text-white" />
                        </div>
                        <!-- Salesforce icon -->
                        <div
                          class="w-5 h-5 rounded-full bg-blue-500 flex items-center justify-center ring-2 ring-white z-10"
                          title="Salesforce"
                        >
                          <.icon name="hero-cloud" class="size-3 text-white" />
                        </div>
                      </div>
                    </div>

                    <button
                      type="button"
                      id="chat-submit-btn"
                      phx-click={JS.dispatch("chat:submit", to: "#mention-input")}
                      disabled={@mentions == [] || @message_input == ""}
                      class="p-2 bg-slate-700 text-white rounded-lg hover:bg-slate-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                    >
                      <.icon name="hero-paper-airplane" class="size-4" />
                    </button>
                  </div>
                </div>
              </div>
            <% else %>
              <!-- History View -->
              <div class="flex-1 overflow-y-auto">
                <div :for={thread <- @threads} class="border-b border-slate-100">
                  <button
                    phx-click="select_thread"
                    phx-value-id={thread.id}
                    class="w-full p-4 text-left hover:bg-slate-50 transition-colors"
                  >
                    <div class="font-medium text-slate-800 truncate">
                      {thread.title || "New Chat"}
                    </div>
                    <div class="text-sm text-slate-500">
                      {Calendar.strftime(thread.updated_at, "%b %d, %Y")}
                    </div>
                  </button>
                </div>

                <div :if={@threads == []} class="p-8 text-center text-slate-400">
                  <.icon name="hero-inbox" class="size-10 mx-auto mb-2" />
                  <p class="text-sm">No conversations yet</p>
                </div>
              </div>
            <% end %>
          </div>
        </:body>
      </.drawer>
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
      |> assign(:active_tab, :chat)
      |> assign(:mentions, [])
      |> assign(:message_input, "")
      |> push_event("clear_input", %{})

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
      |> assign(:active_tab, :chat)

    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => "chat"}, socket) do
    {:noreply, assign(socket, :active_tab, :chat)}
  end

  def handle_event("switch_tab", %{"tab" => "history"}, socket) do
    threads = Chat.list_threads(socket.assigns.current_user)

    socket =
      socket
      |> assign(:active_tab, :history)
      |> assign(:threads, threads)

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
      |> assign(:active_tab, :history)
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
    do: "bg-slate-700 text-white rounded-lg px-4 py-2 max-w-[80%]"

  defp message_bubble_class(_),
    do: "bg-slate-100 text-slate-800 rounded-lg px-4 py-2 max-w-[80%]"

  defp format_thread_timestamp(datetime) do
    # Format: "11:17am - November 13, 2025"
    time = Calendar.strftime(datetime, "%-I:%M%P")
    date = Calendar.strftime(datetime, "%B %-d, %Y")
    "#{time} - #{date}"
  end

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
        ~s(<span class="inline-flex items-center gap-1 bg-slate-100 text-slate-700 rounded-full px-2 py-0.5 text-sm font-medium"><img src="https://ui-avatars.com/api/?name=#{encoded_name}&size=20&background=475569&color=fff&bold=true" class="w-5 h-5 rounded-full" alt="#{first_name}"/>#{first_name}</span>)

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
      ~s(<a href="/dashboard/meetings/\\2" class="text-slate-600 hover:text-slate-800 underline font-medium">\\1</a>)
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
