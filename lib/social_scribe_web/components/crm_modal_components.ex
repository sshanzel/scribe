defmodule SocialScribeWeb.CRMModalComponents do
  @moduledoc """
  Reusable UI components specific to CRM update modals.

  These components are shared between HubSpot, Salesforce, and other CRM modals.
  For generic modal components, see `SocialScribeWeb.ModalComponents`.
  """
  use Phoenix.Component

  import SocialScribeWeb.ModalComponents, only: [suggestion_card: 1, modal_footer: 1, empty_state: 1]
  import SocialScribeWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders a CRM modal header with title and description.

  ## Examples

      <.crm_modal_header
        modal_id="hubspot-modal"
        title="Update in HubSpot"
      />
  """
  attr :modal_id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil

  def crm_modal_header(assigns) do
    assigns =
      assign_new(assigns, :description, fn ->
        "Here are suggested updates to sync with your integrations based on this meeting"
      end)

    ~H"""
    <div>
      <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">
        {@title}
      </h2>
      <p id={"#{@modal_id}-description"} class="mt-2 text-base font-light leading-7 text-slate-500">
        {@description}
      </p>
    </div>
    """
  end

  @doc """
  Renders the suggestions section for CRM modals.

  Shows loading state, empty state, or suggestion cards with form.

  ## Examples

      <.suggestions_section
        suggestions={@suggestions}
        loading={@loading}
        myself={@myself}
        patch={@patch}
        submit_text="Update HubSpot"
        submit_class="bg-hubspot-button hover:bg-hubspot-button-hover"
      />
  """
  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true
  attr :submit_text, :string, default: "Update"
  attr :submit_class, :string, default: "bg-green-600 hover:bg-green-700"

  def suggestions_section(assigns) do
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
              submit_text={@submit_text}
              submit_class={@submit_class}
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
end
