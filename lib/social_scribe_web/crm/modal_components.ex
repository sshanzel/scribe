defmodule SocialScribeWeb.CRM.ModalComponents do
  @moduledoc """
  Reusable UI components specific to CRM update modals.

  These components are shared between HubSpot, Salesforce, and other CRM modals.
  For generic modal components, see `SocialScribeWeb.ModalComponents`.
  This module lives under the `SocialScribeWeb.CRM` namespace to group CRM-specific components.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import SocialScribeWeb.ModalComponents,
    only: [modal_footer: 1, empty_state: 1, inline_error: 1]

  import SocialScribeWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders a searchable contact select box.

  Shows selected contact with avatar, or search input when no contact selected.
  Auto-searches when typing, dropdown shows results.

  ## Examples

      <.contact_select
        selected_contact={@selected_contact}
        contacts={@contacts}
        loading={@loading}
        open={@dropdown_open}
        query={@query}
        target={@myself}
      />
  """
  attr :selected_contact, :map, default: nil
  attr :contacts, :list, default: []
  attr :loading, :boolean, default: false
  attr :open, :boolean, default: false
  attr :query, :string, default: ""
  attr :target, :any, default: nil
  attr :error, :string, default: nil
  attr :id, :string, default: "contact-select"

  def contact_select(assigns) do
    ~H"""
    <div class="space-y-1">
      <label
        for={if @selected_contact, do: "#{@id}-button", else: "#{@id}-input"}
        class="block text-sm font-medium text-slate-700"
      >
        Select Contact
      </label>
      <div class="relative">
        <%= if @selected_contact do %>
          <button
            id={"#{@id}-button"}
            type="button"
            phx-click="toggle_contact_dropdown"
            phx-target={@target}
            role="combobox"
            aria-haspopup="listbox"
            aria-expanded={to_string(@open)}
            aria-controls={"#{@id}-listbox"}
            class="relative w-full bg-white border border-hubspot-input rounded-lg pl-1.5 pr-10 py-[5px] text-left cursor-pointer focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm"
          >
            <span class="flex items-center">
              <.avatar
                firstname={@selected_contact.firstname}
                lastname={@selected_contact.lastname}
                size={:sm}
              />
              <span class="ml-1.5 block truncate text-slate-900">
                {@selected_contact.firstname} {@selected_contact.lastname}
              </span>
            </span>
            <span class="absolute inset-y-0 right-0 flex items-center pr-2 pointer-events-none">
              <.icon name="hero-chevron-up-down" class="h-5 w-5 text-hubspot-icon" />
            </span>
          </button>
        <% else %>
          <div class="relative">
            <input
              id={"#{@id}-input"}
              type="text"
              name="contact_query"
              value={@query}
              placeholder="Search contacts..."
              phx-keyup="contact_search"
              phx-target={@target}
              phx-focus="open_contact_dropdown"
              phx-debounce="150"
              autocomplete="off"
              role="combobox"
              aria-autocomplete="list"
              aria-expanded={to_string(@open)}
              aria-controls={"#{@id}-listbox"}
              class="w-full bg-white border border-hubspot-input rounded-lg pl-2 pr-10 py-[5px] text-left focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm"
            />
            <span class="absolute inset-y-0 right-0 flex items-center pr-2 pointer-events-none">
              <%= if @loading do %>
                <.icon name="hero-arrow-path" class="h-5 w-5 text-hubspot-icon animate-spin" />
              <% else %>
                <.icon name="hero-chevron-up-down" class="h-5 w-5 text-hubspot-icon" />
              <% end %>
            </span>
          </div>
        <% end %>

        <div
          :if={@open && (@selected_contact || Enum.any?(@contacts) || @loading || @query != "")}
          id={"#{@id}-listbox"}
          role="listbox"
          phx-click-away="close_contact_dropdown"
          phx-target={@target}
          class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm"
        >
          <button
            :if={@selected_contact}
            type="button"
            phx-click="clear_contact"
            phx-target={@target}
            role="option"
            aria-selected="false"
            class="w-full text-left px-4 py-2 hover:bg-slate-50 text-sm text-slate-700 cursor-pointer"
          >
            Clear selection
          </button>
          <div :if={@loading} class="px-4 py-2 text-sm text-gray-500">
            Searching...
          </div>
          <div
            :if={!@loading && Enum.empty?(@contacts) && @query != ""}
            class="px-4 py-2 text-sm text-gray-500"
          >
            No contacts found
          </div>
          <button
            :for={contact <- @contacts}
            type="button"
            phx-click="select_contact"
            phx-value-id={contact.id}
            phx-target={@target}
            role="option"
            aria-selected="false"
            class="w-full text-left px-4 py-2 hover:bg-slate-50 flex items-center space-x-3 cursor-pointer"
          >
            <.avatar firstname={contact.firstname} lastname={contact.lastname} size={:sm} />
            <div>
              <div class="text-sm font-medium text-slate-900">
                {contact.firstname} {contact.lastname}
              </div>
              <div class="text-xs text-slate-500">
                {contact.email}
              </div>
            </div>
          </button>
        </div>
      </div>
      <.inline_error :if={@error} message={@error} />
    </div>
    """
  end

  @doc """
  Renders an avatar with initials.

  ## Examples

      <.avatar firstname="John" lastname="Doe" size={:md} />
  """
  attr :firstname, :string, default: ""
  attr :lastname, :string, default: ""
  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :class, :string, default: nil

  def avatar(assigns) do
    size_classes = %{
      sm: "h-6 w-6 text-[10px]",
      md: "h-8 w-8 text-[10px]",
      lg: "h-10 w-10 text-sm"
    }

    assigns = assign(assigns, :size_class, size_classes[assigns.size])

    ~H"""
    <div class={[
      "rounded-full bg-hubspot-avatar flex items-center justify-center font-semibold text-hubspot-avatar-text flex-shrink-0",
      @size_class,
      @class
    ]}>
      {String.at(@firstname || "", 0)}{String.at(@lastname || "", 0)}
    </div>
    """
  end

  @doc """
  Renders a clickable contact list item.

  ## Examples

      <.contact_list_item
        contact={%{firstname: "John", lastname: "Doe", email: "john@example.com"}}
        on_click="select_contact"
        target={@myself}
      />
  """
  attr :contact, :map, required: true
  attr :on_click, :string, required: true
  attr :target, :any, default: nil
  attr :class, :string, default: nil

  def contact_list_item(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@on_click}
      phx-value-id={@contact.id}
      phx-target={@target}
      class={[
        "w-full px-4 py-3 text-left hover:bg-slate-50 transition-colors flex items-center space-x-3",
        @class
      ]}
    >
      <.avatar firstname={@contact.firstname} lastname={@contact.lastname} size={:md} />
      <div>
        <div class="text-sm font-medium text-slate-900">
          {@contact.firstname} {@contact.lastname}
        </div>
        <div class="text-xs text-slate-500">
          {@contact.email}
          <span :if={@contact[:company]} class="text-slate-400">· {@contact.company}</span>
        </div>
      </div>
    </button>
    """
  end

  @doc """
  Renders a contact list container.

  ## Examples

      <.contact_list>
        <.contact_list_item :for={c <- @contacts} contact={c} on_click="select" />
      </.contact_list>
  """
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def contact_list(assigns) do
    ~H"""
    <div class={[
      "border border-gray-200 rounded-md divide-y divide-gray-200 max-h-64 overflow-y-auto bg-white shadow-sm",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a value comparison (old → new).

  ## Examples

      <.value_comparison
        current_value="old@email.com"
        new_value="new@email.com"
      />
  """
  attr :current_value, :string, default: nil
  attr :new_value, :string, required: true
  attr :class, :string, default: nil

  def value_comparison(assigns) do
    ~H"""
    <div class={["flex items-center gap-6", @class]}>
      <div class="flex-1">
        <input
          type="text"
          readonly
          value={@current_value || ""}
          placeholder="No existing value"
          class={[
            "block w-full shadow-sm text-sm bg-white border border-hubspot-input rounded-[7px] py-1.5 px-2",
            if(@current_value && @current_value != "",
              do: "line-through text-slate-500",
              else: "text-slate-400"
            )
          ]}
        />
      </div>
      <div class="text-slate-300">
        <.icon name="hero-arrow-long-right" class="h-6 w-6" />
      </div>
      <div class="flex-1">
        <input
          type="text"
          readonly
          value={@new_value}
          class="block w-full shadow-sm text-sm text-slate-900 bg-white border border-hubspot-input rounded-[7px] py-1.5 px-2 focus:ring-blue-500 focus:border-blue-500"
        />
      </div>
    </div>
    """
  end

  @doc """
  Renders a suggestion card with checkbox.

  ## Examples

      <.suggestion_card suggestion={%{field: "email", label: "Email", ...}} />
  """
  attr :suggestion, :map, required: true
  attr :class, :string, default: nil

  def suggestion_card(assigns) do
    ~H"""
    <div class={["bg-hubspot-card rounded-2xl p-6 mb-4", @class]}>
      <div class="flex items-start justify-between">
        <div class="flex items-start gap-3">
          <div class="flex items-center h-5 pt-0.5">
            <input
              type="checkbox"
              checked={@suggestion.apply}
              phx-click={JS.dispatch("click", to: "#suggestion-apply-#{@suggestion.field}")}
              class="h-4 w-4 rounded-[3px] border-slate-300 text-hubspot-checkbox accent-hubspot-checkbox focus:ring-0 focus:ring-offset-0 cursor-pointer"
            />
          </div>
          <div class="text-sm font-semibold text-slate-900 leading-5">{@suggestion.label}</div>
        </div>

        <div class="flex items-center gap-3 pt-0.5">
          <span
            class={[
              "inline-flex items-center rounded-full bg-hubspot-pill px-2 py-1 text-xs font-medium text-hubspot-pill-text",
              if(@suggestion.apply, do: "opacity-100", else: "opacity-0 pointer-events-none")
            ]}
            aria-hidden={to_string(!@suggestion.apply)}
          >
            1 update selected
          </span>
          <button
            type="button"
            class="text-xs text-hubspot-hide hover:text-hubspot-hide-hover font-medium"
          >
            Hide details
          </button>
        </div>
      </div>

      <div class="mt-2 pl-8">
        <div class="text-sm font-medium text-slate-700 leading-5 ml-1">{@suggestion.label}</div>

        <div class="relative mt-2">
          <input
            id={"suggestion-apply-#{@suggestion.field}"}
            type="checkbox"
            name={"apply[#{@suggestion.field}]"}
            value="1"
            checked={@suggestion.apply}
            class="absolute -left-8 top-1/2 -translate-y-1/2 h-4 w-4 rounded-[3px] border-slate-300 text-hubspot-checkbox accent-hubspot-checkbox focus:ring-0 focus:ring-offset-0 cursor-pointer"
          />

          <div class="grid grid-cols-[1fr_32px_1fr] items-center gap-6">
            <input
              type="text"
              readonly
              value={@suggestion.current_value || ""}
              placeholder="No existing value"
              class={[
                "block w-full shadow-sm text-sm bg-white border border-gray-300 rounded-[7px] py-1.5 px-2",
                if(@suggestion.current_value && @suggestion.current_value != "",
                  do: "line-through text-gray-500",
                  else: "text-gray-400"
                )
              ]}
            />

            <div class="w-8 flex justify-center text-hubspot-arrow">
              <.icon name="hero-arrow-long-right" class="h-7 w-7" />
            </div>

            <input
              type="text"
              name={"values[#{@suggestion.field}]"}
              value={@suggestion.new_value}
              class="block w-full shadow-sm text-sm text-slate-900 bg-white border border-hubspot-input rounded-[7px] py-1.5 px-2 focus:ring-blue-500 focus:border-blue-500"
            />
          </div>
        </div>

        <div class="mt-3 grid grid-cols-[1fr_32px_1fr] items-start gap-6">
          <button
            type="button"
            class="text-xs text-hubspot-link hover:text-hubspot-link-hover font-medium justify-self-start"
          >
            Update mapping
          </button>
          <span></span>
          <span :if={@suggestion[:timestamp]} class="text-xs text-slate-500 justify-self-start">
            Found in transcript<span
              class="text-hubspot-link hover:underline cursor-help"
              title={@suggestion[:context]}
            >
              ({@suggestion[:timestamp]})
            </span>
          </span>
        </div>
      </div>
    </div>
    """
  end

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
      if is_nil(assigns.description) do
        assign(
          assigns,
          :description,
          "Here are suggested updates to sync with your integrations based on this meeting"
        )
      else
        assigns
      end

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
  attr :submitting, :boolean, default: false
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
          <p><%= if @submitting, do: "Updating contact...", else: "Generating suggestions..." %></p>
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

  @doc """
  Renders a HubSpot-styled modal wrapper.

  This is a specialized modal with HubSpot-specific styling:
  - Custom overlay color
  - Reduced padding
  - No close button (relies on Cancel button in footer)

  ## Examples

      <.hubspot_modal id="hubspot-modal" show on_cancel={JS.patch(~p"/back")}>
        Modal content here
      </.hubspot_modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def hubspot_modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="bg-hubspot-overlay/90 fixed inset-0 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white px-10 py-7 shadow-lg ring-1 transition min-h-[420px]"
            >
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a Salesforce-styled modal wrapper.

  This is a specialized modal with Salesforce-specific styling:
  - Custom overlay color
  - Reduced padding
  - No close button (relies on Cancel button in footer)

  ## Examples

      <.salesforce_modal id="salesforce-modal" show on_cancel={JS.patch(~p"/back")}>
        Modal content here
      </.salesforce_modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true

  def salesforce_modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="bg-salesforce-overlay/90 fixed inset-0 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white px-10 py-7 shadow-lg ring-1 transition min-h-[420px]"
            >
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-container",
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-container")
  end

  defp hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      time: 200,
      transition: {"transition-all ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end
end
