defmodule SocialScribeWeb.MeetingLive.HubspotModalComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents, only: [contact_select: 1]
  import SocialScribeWeb.CRMModalComponents

  alias SocialScribeWeb.MeetingLive.CRMModalHelpers

  # CRM-specific configuration
  @crm_config %{
    search_message: :hubspot_search,
    generate_message: :generate_suggestions,
    apply_message: :apply_hubspot_updates,
    title: "Update in HubSpot",
    submit_text: "Update HubSpot",
    submit_class: "bg-hubspot-button hover:bg-hubspot-button-hover"
  }

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "hubspot-modal-wrapper" end)
    assigns = assign(assigns, :config, @crm_config)

    ~H"""
    <div class="space-y-6">
      <.crm_modal_header modal_id={@modal_id} title={@config.title} />

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
          submit_text={@config.submit_text}
          submit_class={@config.submit_class}
        />
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, CRMModalHelpers.default_assigns())}
  end

  @impl true
  def update(assigns, socket) do
    CRMModalHelpers.handle_update(socket, assigns, @crm_config)
  end

  # Event handlers delegate to shared helpers

  @impl true
  def handle_event("contact_search", params, socket) do
    CRMModalHelpers.handle_contact_search(socket, params, @crm_config)
  end

  @impl true
  def handle_event("open_contact_dropdown", _params, socket) do
    CRMModalHelpers.handle_open_contact_dropdown(socket)
  end

  @impl true
  def handle_event("close_contact_dropdown", _params, socket) do
    CRMModalHelpers.handle_close_contact_dropdown(socket)
  end

  @impl true
  def handle_event("toggle_contact_dropdown", _params, socket) do
    CRMModalHelpers.handle_toggle_contact_dropdown(socket, @crm_config)
  end

  @impl true
  def handle_event("select_contact", params, socket) do
    CRMModalHelpers.handle_select_contact(socket, params, @crm_config)
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    CRMModalHelpers.handle_clear_contact(socket)
  end

  @impl true
  def handle_event("toggle_suggestion", params, socket) do
    CRMModalHelpers.handle_toggle_suggestion(socket, params)
  end

  @impl true
  def handle_event("apply_updates", %{"apply" => _selected, "values" => _values} = params, socket) do
    CRMModalHelpers.handle_apply_updates(socket, params, @crm_config)
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    CRMModalHelpers.handle_apply_updates_empty(socket)
  end
end
