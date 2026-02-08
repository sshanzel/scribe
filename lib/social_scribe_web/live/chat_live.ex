defmodule SocialScribeWeb.ChatLive do
  @moduledoc """
  LiveView for the floating chat interface.
  This is embedded in the dashboard layout.
  """
  use SocialScribeWeb, :live_view

  on_mount {SocialScribeWeb.UserAuth, :mount_current_user}

  alias Phoenix.LiveView.AsyncResult
  alias SocialScribe.Chat
  alias SocialScribe.Contacts
  alias SocialScribe.ChatAIApi

  @impl true
  def mount(_params, _session, socket) do
    # No layout for embedded LiveView to avoid duplicate flash groups
    # This component floats across navigation, so threads are loaded
    # only when the history tab is opened (not on mount)
    socket =
      socket
      |> assign(:open, false)
      |> assign(:animate, true)
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
      # Threads not loaded yet - will be fetched when history tab opens
      |> assign(:threads, nil)

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

      <.drawer id="chat-drawer" open={@open} animate={@animate} on_close="toggle_chat">
        <:header>
          <h3 class="font-semibold text-slate-800 text-base">Ask Anything</h3>
        </:header>
        <:body>
          <!-- Tab Bar -->
          <div class="flex items-center justify-between px-3 py-1.5">
            <div class="flex gap-1">
              <button
                phx-click="switch_tab"
                phx-value-tab="chat"
                class={"px-2.5 py-1 text-sm font-medium rounded-md transition-colors " <>
                  if(@active_tab == :chat,
                    do: "bg-[#f0f5f5] text-slate-800",
                    else: "text-slate-600 hover:bg-slate-100"
                  )}
              >
                Chat
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="history"
                class={"px-2.5 py-1 text-sm font-medium rounded-md transition-colors " <>
                  if(@active_tab == :history,
                    do: "bg-[#f0f5f5] text-slate-800",
                    else: "text-slate-600 hover:bg-slate-100"
                  )}
              >
                History
              </button>
            </div>
            <button
              phx-click="reset_chat"
              class="p-1 text-slate-500 hover:text-slate-700 hover:bg-slate-100 rounded-full transition-colors"
              title="New chat"
            >
              <.icon name="hero-plus" class="size-4" />
            </button>
          </div>
          
    <!-- Content Area -->
          <div class="flex-1 overflow-hidden flex flex-col">
            <%= if @active_tab == :chat do %>
              <!-- Messages View -->
              <div
                id="messages-container"
                class="flex-1 overflow-y-auto p-3 space-y-3 flex flex-col"
                phx-hook="ScrollToBottom"
              >
                <!-- Timestamp -->
                <.timestamp_separator datetime={
                  cond do
                    @current_thread -> @current_thread.inserted_at
                    true -> DateTime.utc_now()
                  end
                } />
                
    <!-- Persistent welcome message (always first) -->
                <div class="flex justify-start">
                  <div class="text-slate-800 px-3 py-2 max-w-[85%]">
                    <div class="text-sm leading-relaxed">
                      I can answer questions about Jump meetings and data — just ask!
                    </div>
                    <.sources_indicator :if={!has_assistant_message?(@messages)} />
                  </div>
                </div>

                <%= if @current_thread do %>
                  <div
                    :for={{message, index} <- Enum.with_index(@messages)}
                    class={message_class(message.role)}
                  >
                    <div class={message_bubble_class(message.role)}>
                      <div class="text-sm leading-relaxed">
                        {raw(render_message_content(message))}
                      </div>
                      <!-- Sources for the last assistant message -->
                      <.sources_indicator :if={
                        message.role != "user" && index == length(@messages) - 1
                      } />
                    </div>
                  </div>

                  <.loading_indicator loading={@loading} />
                  <.error_alert :if={@error_message} message={@error_message} />
                <% end %>
              </div>
              
    <!-- Message Input Container -->
              <div class="p-2">
                <div class="rounded-lg border border-slate-200 bg-white">
                  <!-- Row 1: Add context button -->
                  <div class="px-2.5 pt-1.5">
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
                      class="min-h-[50px] max-h-[100px] overflow-y-auto w-full focus:outline-none text-sm px-2.5 py-1.5 empty:before:content-[attr(data-placeholder)] empty:before:text-slate-400"
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
                        class="w-full px-2.5 py-2 text-left hover:bg-slate-50 flex items-center gap-2"
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
                  <div class="px-2.5 py-1.5 flex items-center justify-between">
                    <!-- Sources - always displayed -->
                    <div class="flex items-center gap-1.5">
                      <span class="text-xs text-slate-400">Sources</span>
                      <div class="flex -space-x-2">
                        <!-- Jump AI logo -->
                        <div
                          class="w-5 h-5 rounded-full bg-[#f0f5f5] flex items-center justify-center ring-1 ring-white z-40"
                          title="Jump AI Meetings"
                        >
                          <img src={~p"/images/jump-logo.svg"} class="w-3 h-3" />
                        </div>
                        <!-- Gmail logo -->
                        <div
                          class="w-5 h-5 rounded-full bg-[#f0f5f5] flex items-center justify-center ring-1 ring-white z-30"
                          title="Gmail"
                        >
                          <img src={~p"/images/gmail-logo.svg"} class="w-3 h-3" />
                        </div>
                        <!-- HubSpot logo -->
                        <div
                          class="w-5 h-5 rounded-full bg-[#f0f5f5] flex items-center justify-center ring-1 ring-white z-20"
                          title="HubSpot"
                        >
                          <img src={~p"/images/hubspot-logo.svg"} class="w-3 h-3" />
                        </div>
                        <!-- Salesforce logo -->
                        <div
                          class="w-5 h-5 rounded-full bg-[#f0f5f5] flex items-center justify-center ring-1 ring-white z-10"
                          title="Salesforce"
                        >
                          <img src={~p"/images/salesforce-logo.svg"} class="w-3 h-3" />
                        </div>
                      </div>
                    </div>

                    <button
                      type="button"
                      id="chat-submit-btn"
                      phx-click={JS.dispatch("chat:submit", to: "#mention-input")}
                      disabled={@message_input == ""}
                      class="w-7 h-7 shrink-0 flex items-center justify-center bg-slate-700 text-white rounded-md hover:bg-slate-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                    >
                      <.icon name="hero-paper-airplane" class="size-3.5" />
                    </button>
                  </div>
                </div>
              </div>
            <% else %>
              <!-- History View -->
              <div class="flex-1 overflow-y-auto flex flex-col">
                <%= if is_nil(@threads) or @threads.loading do %>
                  <!-- Loading state -->
                  <div class="flex-1 flex flex-col items-center justify-center text-slate-400 py-6">
                    <.icon name="hero-arrow-path" class="size-6 mb-2 animate-spin" />
                    <p class="text-sm">Loading...</p>
                  </div>
                <% else %>
                  <% threads = get_threads(@threads) %>
                  <div :for={thread <- threads} class="border-b border-slate-100">
                    <button
                      phx-click="select_thread"
                      phx-value-id={thread.id}
                      class="w-full p-3 text-left hover:bg-slate-50 transition-colors"
                    >
                      <div class="font-medium text-sm text-slate-800 truncate">
                        {thread.title || "New Chat"}
                      </div>
                      <div class="text-xs text-slate-500">
                        {Calendar.strftime(thread.updated_at, "%b %d, %Y")}
                      </div>
                    </button>
                  </div>

                  <div
                    :if={threads == []}
                    class="flex-1 flex flex-col items-center justify-center text-slate-400 py-6"
                  >
                    <.icon name="hero-inbox" class="size-8 mb-2 -mt-32" />
                    <p class="text-sm">No conversations yet</p>
                  </div>
                <% end %>
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
    new_open = !socket.assigns.open

    socket =
      if new_open do
        # Threads already loaded on mount, just open with animation
        # Clear animation flag after render to prevent re-animation on navigation
        Process.send_after(self(), :clear_animate, 300)
        assign(socket, open: true, animate: true)
      else
        assign(socket, open: false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("reset_chat", _params, socket) do
    # Reset chat state without creating a thread entity
    # Thread will be created when user sends first message
    socket =
      socket
      |> assign(:current_thread, nil)
      |> assign(:messages, [])
      |> assign(:active_tab, :chat)
      |> assign(:mentions, [])
      |> assign(:message_input, "")
      |> assign(:error_message, nil)
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
    socket = assign(socket, :active_tab, :history)

    # Fetch threads when opening history tab (if user is available)
    socket =
      if socket.assigns[:current_user] do
        user = socket.assigns.current_user

        assign_async(socket, :threads, fn ->
          {:ok, %{threads: Chat.list_threads(user)}}
        end)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("back_to_threads", _params, socket) do
    socket =
      socket
      |> assign(:current_thread, nil)
      |> assign(:messages, [])
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
  def handle_event("send_message", %{"message" => content, "mentions" => _mentions_data}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      # Create thread if one doesn't exist
      {thread, socket} =
        case socket.assigns.current_thread do
          nil ->
            {:ok, new_thread} = Chat.create_thread(socket.assigns.current_user)
            current_threads = get_threads(socket.assigns.threads)

            socket =
              socket
              |> assign(:current_thread, new_thread)
              |> assign(:threads, AsyncResult.ok(%{threads: [new_thread | current_threads]}))

            {new_thread, socket}

          existing_thread ->
            {existing_thread, socket}
        end

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

      # Create optimistic user message for immediate display
      optimistic_message = %{
        id: "pending-#{System.unique_integer()}",
        role: "user",
        content: content,
        metadata: metadata,
        inserted_at: DateTime.utc_now()
      }

      # Show loading state, add optimistic message, clear input
      socket =
        socket
        |> assign(:loading, true)
        |> assign(:error_message, nil)
        |> assign(:message_input, "")
        |> assign(:mentions, [])
        |> assign(:messages, socket.assigns.messages ++ [optimistic_message])
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

  @impl true
  def handle_info(:clear_animate, socket) do
    {:noreply, assign(socket, :animate, false)}
  end

  # =============================================================================
  # Function Components
  # =============================================================================

  # Renders the loading indicator shown when AI is generating a response.
  attr :loading, :boolean, required: true

  defp loading_indicator(assigns) do
    ~H"""
    <div :if={@loading} class="flex justify-start">
      <div class="bg-slate-100 rounded-lg px-3 py-1.5 text-slate-500">
        <span class="animate-pulse text-sm">Thinking...</span>
      </div>
    </div>
    """
  end

  # Renders an error message with dismiss button.
  attr :message, :string, required: true

  defp error_alert(assigns) do
    ~H"""
    <div class="flex justify-start">
      <div class="bg-red-50 border border-red-200 rounded-lg px-3 py-2 text-red-700 max-w-[85%]">
        <div class="flex items-start gap-1.5">
          <.icon name="hero-exclamation-circle" class="size-4 flex-shrink-0 mt-0.5" />
          <div>
            <p class="text-sm">{@message}</p>
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
    """
  end

  # Renders an empty state message.
  attr :icon, :string, default: "hero-chat-bubble-left-right"
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  defp empty_state(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col items-center justify-center text-slate-400 py-6">
      <.icon name={@icon} class="size-10 mb-2" />
      <p class="text-sm">{@title}</p>
      <p :if={@subtitle} class="text-xs mt-1">{@subtitle}</p>
    </div>
    """
  end

  # Renders the timestamp separator between messages.
  attr :datetime, :any, required: true

  defp timestamp_separator(assigns) do
    ~H"""
    <div class="flex items-center gap-3 pb-1 mx-1">
      <div class="flex-1 h-px bg-slate-200"></div>
      <span class="text-xs text-slate-400 whitespace-nowrap">
        {format_thread_timestamp(@datetime)}
      </span>
      <div class="flex-1 h-px bg-slate-200"></div>
    </div>
    """
  end

  # Renders the sources indicator for assistant messages.
  defp sources_indicator(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5 mt-2">
      <span class="text-xs text-slate-400">Sources</span>
      <div
        class="w-5 h-5 rounded-full bg-[#f0f5f5] flex items-center justify-center"
        title="Jump AI Meetings"
      >
        <img src={~p"/images/jump-logo.svg"} class="w-3 h-3" />
      </div>
    </div>
    """
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp get_threads(%AsyncResult{ok?: true, result: threads}) when is_list(threads), do: threads
  defp get_threads(_), do: []

  defp has_assistant_message?(messages) do
    Enum.any?(messages, fn msg -> msg.role != "user" end)
  end

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
    do: "bg-[#f0f5f5] text-slate-800 rounded-lg px-3 py-2 max-w-[85%]"

  defp message_bubble_class(_),
    do: "text-slate-800 px-3 py-2 max-w-[85%]"

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
      initial = String.first(name) |> String.upcase()

      # The @ was already escaped, so match the escaped version
      pattern = "@#{escape_html(name)}"

      # Use same styling as the input mention chip (hooks.js)
      avatar_html = mention_chip_html(initial, first_name)

      String.replace(acc, pattern, avatar_html)
    end)
  end

  # Shared mention chip HTML - keep in sync with assets/js/hooks.js MentionInput
  defp mention_chip_html(initial, display_name) do
    ~s(<span class="mention-chip inline-flex items-center gap-1 bg-slate-200 text-slate-700 px-1 py-px rounded-full text-xs font-medium"><span class="relative"><span class="w-4 h-4 bg-slate-500 rounded-full flex items-center justify-center text-[10px] text-white font-medium">#{initial}</span><img src="/images/jump-logo.svg" class="absolute -bottom-0.5 -right-1 w-2.5 h-2.5 bg-[#f0f5f5] rounded-full p-px border-0" /></span><span>#{display_name}</span></span>)
  end

  defp render_meeting_links(content, []), do: content

  defp render_meeting_links(content, _meeting_refs) do
    # Convert [Meeting: title (date)](meeting:123) to clickable links
    # Use data-phx-link="redirect" for LiveView navigation (no full page reload)
    Regex.replace(
      ~r/\[Meeting:\s*(.+?)\]\(meeting:(\d+)\)/,
      content,
      ~s(<a href="/dashboard/meetings/\\2" data-phx-link="redirect" data-phx-link-state="push" class="text-slate-600 hover:text-slate-800 underline font-medium">\\1</a><img src="/images/jump-logo.svg" class="w-3 h-3 inline ml-1 align-baseline" />)
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
