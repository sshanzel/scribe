defmodule SocialScribeWeb.MeetingLive.SalesforceModalComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "salesforce-modal-wrapper" end)

    ~H"""
    <div class="space-y-6">
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">
          Update in Salesforce
        </h2>
        <p id={"#{@modal_id}-description"} class="mt-2 text-base font-light leading-7 text-slate-500">
          Here are suggested updates to sync with your integrations based on this
          <span class="block">meeting</span>
        </p>
      </div>

      <.contact_select
        selected_contact={@selected_contact}
        contacts={@contacts}
        loading={@searching}
        open={@dropdown_open}
        query={@query}
        target={@myself}
        error={@error}
      />

      <%= if @selected_contact do %>
        <.suggestions_section
          suggestions={@suggestions}
          loading={@loading}
          myself={@myself}
          patch={@patch}
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true

  defp suggestions_section(assigns) do
    assigns = assign(assigns, :selected_count, Enum.count(assigns.suggestions, & &1.apply))

    ~H"""
    <div class="space-y-4">
      <%= if @loading do %>
        <div class="text-center py-8 text-slate-500">
          <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin mx-auto mb-2" />
          <p>Generating suggestions...</p>
        </div>
      <% else %>
        <%= if Enum.empty?(@suggestions) do %>
          <.empty_state
            message="No update suggestions found from this meeting."
            submessage="The AI didn't detect any new contact information in the transcript."
          />
        <% else %>
          <form phx-submit="apply_updates" phx-change="toggle_suggestion" phx-target={@myself}>
            <div class="space-y-4 max-h-[60vh] overflow-y-auto pr-2">
              <.suggestion_card :for={suggestion <- @suggestions} suggestion={suggestion} />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text="Update Salesforce"
              submit_class="bg-salesforce-button hover:bg-salesforce-button-hover"
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={"1 object, #{@selected_count} fields in 1 integration selected to update"}
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       step: :search,
       query: "",
       contacts: [],
       selected_contact: nil,
       suggestions: [],
       loading: false,
       searching: false,
       dropdown_open: false,
       error: nil,
       auto_searched: false,
       auto_select_single: false,
       auto_select_query: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_select_all_suggestions(assigns)
      |> maybe_auto_search_participant(assigns)
      |> maybe_auto_select_single_contact(assigns)

    {:ok, socket}
  end

  defp maybe_select_all_suggestions(socket, %{suggestions: suggestions})
       when is_list(suggestions) do
    assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
  end

  defp maybe_select_all_suggestions(socket, _assigns), do: socket

  # Auto-select contact when:
  # 1. auto_select_single is true (only one non-host participant)
  # 2. Contacts just came in from search
  # 3. No contact is currently selected
  defp maybe_auto_select_single_contact(socket, %{contacts: contacts})
       when is_list(contacts) and length(contacts) > 0 do
    if socket.assigns.auto_select_single and is_nil(socket.assigns.selected_contact) do
      query = socket.assigns.auto_select_query || socket.assigns.query
      contact = find_best_matching_contact(contacts, query)

      if contact do
        socket =
          assign(socket,
            loading: true,
            selected_contact: contact,
            error: nil,
            dropdown_open: false,
            query: "",
            suggestions: [],
            auto_select_single: false
          )

        send(
          self(),
          {:generate_salesforce_suggestions, contact, socket.assigns.meeting,
           socket.assigns.credential}
        )

        socket
      else
        socket
      end
    else
      socket
    end
  end

  defp maybe_auto_select_single_contact(socket, _assigns), do: socket

  # Find the best matching contact - prioritize exact name match, otherwise take first result
  defp find_best_matching_contact(contacts, query) when is_binary(query) do
    query_lower = String.downcase(query)

    # First try exact match
    exact_match =
      Enum.find(contacts, fn contact ->
        full_name = "#{contact.firstname} #{contact.lastname}"
        String.downcase(full_name) == query_lower
      end)

    # If no exact match, take first result
    exact_match || List.first(contacts)
  end

  defp find_best_matching_contact(contacts, _query), do: List.first(contacts)

  # Auto-search for non-host participants when modal opens
  # If only one non-host participant: auto-fill search AND auto-select when results come back
  # If multiple non-host participants: search first one, show dropdown for user to select
  defp maybe_auto_search_participant(socket, assigns) do
    if not socket.assigns.auto_searched and is_nil(socket.assigns.selected_contact) do
      meeting = assigns[:meeting] || socket.assigns[:meeting]

      if meeting && is_list(meeting.meeting_participants) do
        non_host_participants =
          Enum.filter(meeting.meeting_participants, fn p -> not p.is_host end)

        case non_host_participants do
          [single_participant] ->
            # Single attendee - auto-fill and mark for auto-select
            socket =
              assign(socket,
                searching: true,
                auto_searched: true,
                dropdown_open: false,
                query: single_participant.name,
                auto_select_single: true,
                auto_select_query: single_participant.name
              )

            send(self(), {:salesforce_search, single_participant.name, socket.assigns.credential})
            socket

          [first | _rest] ->
            # Multiple attendees - search first one, show dropdown
            socket =
              assign(socket,
                searching: true,
                auto_searched: true,
                dropdown_open: true,
                query: first.name
              )

            send(self(), {:salesforce_search, first.name, socket.assigns.credential})
            socket

          [] ->
            assign(socket, auto_searched: true)
        end
      else
        socket
      end
    else
      socket
    end
  end

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
      send(self(), {:salesforce_search, query, socket.assigns.credential})
      {:noreply, socket}
    else
      {:noreply, assign(socket, query: query, contacts: [], dropdown_open: query != "")}
    end
  end

  @impl true
  def handle_event("open_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: true)}
  end

  @impl true
  def handle_event("close_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  @impl true
  def handle_event("toggle_contact_dropdown", _params, socket) do
    if socket.assigns.dropdown_open do
      {:noreply, assign(socket, dropdown_open: false)}
    else
      socket = assign(socket, dropdown_open: true, searching: true)

      query =
        "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"

      send(self(), {:salesforce_search, query, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

    if contact do
      socket =
        assign(socket,
          loading: true,
          selected_contact: contact,
          error: nil,
          dropdown_open: false,
          query: "",
          suggestions: []
        )

      send(
        self(),
        {:generate_salesforce_suggestions, contact, socket.assigns.meeting,
         socket.assigns.credential}
      )

      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Contact not found")}
    end
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    {:noreply,
     assign(socket,
       step: :search,
       selected_contact: nil,
       suggestions: [],
       loading: false,
       searching: false,
       dropdown_open: false,
       contacts: [],
       query: "",
       error: nil
     )}
  end

  @impl true
  def handle_event("toggle_suggestion", params, socket) do
    applied_fields = Map.get(params, "apply", %{})
    values = Map.get(params, "values", %{})
    checked_fields = Map.keys(applied_fields)

    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        apply? = suggestion.field in checked_fields

        suggestion =
          case Map.get(values, suggestion.field) do
            nil -> suggestion
            new_value -> %{suggestion | new_value: new_value}
          end

        %{suggestion | apply: apply?}
      end)

    {:noreply, assign(socket, suggestions: updated_suggestions)}
  end

  @impl true
  def handle_event("apply_updates", %{"apply" => selected, "values" => values}, socket) do
    socket = assign(socket, loading: true, error: nil)

    updates =
      selected
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        Map.put(acc, field, Map.get(values, field, ""))
      end)

    send(
      self(),
      {:apply_salesforce_updates, updates, socket.assigns.selected_contact,
       socket.assigns.credential}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end
end
