defmodule SocialScribeWeb.ModalComponents do
  @moduledoc """
  Reusable UI components for modals and dialogs.

  For CRM-specific modal components (HubSpot, Salesforce), see `SocialScribeWeb.CRM.ModalComponents`.
  """
  use Phoenix.Component

  import SocialScribeWeb.CoreComponents, only: [icon: 1]

  @doc """
  Renders a search input with icon.

  ## Examples

      <.search_input
        name="query"
        value=""
        placeholder="Search..."
        loading={false}
      />
  """
  attr :name, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: "Search..."
  attr :loading, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def search_input(assigns) do
    ~H"""
    <div class={["relative", @class]}>
      <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
        <.icon name="hero-magnifying-glass" class="h-5 w-5 text-gray-400" />
      </div>
      <input
        type="text"
        name={@name}
        value={@value}
        class="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
        placeholder={@placeholder}
        {@rest}
      />
      <div :if={@loading} class="absolute inset-y-0 right-0 pr-3 flex items-center">
        <.icon name="hero-arrow-path" class="h-4 w-4 text-gray-400 animate-spin" />
      </div>
    </div>
    """
  end

  @doc """
  Renders a success message with checkmark icon.

  ## Examples

      <.success_message title="Success!" message="Operation completed." />
  """
  attr :title, :string, required: true
  attr :message, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block
  slot :actions

  def success_message(assigns) do
    ~H"""
    <div class={["text-center py-8", @class]}>
      <div class="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-green-100 mb-4">
        <.icon name="hero-check" class="h-6 w-6 text-green-600" />
      </div>
      <h3 class="text-lg font-medium text-slate-800 mb-2">{@title}</h3>
      <p :if={@message} class="text-slate-500 mb-6">{@message}</p>
      <div :if={@inner_block != []} class="text-slate-500 mb-6">
        {render_slot(@inner_block)}
      </div>
      <div :if={@actions != []}>
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a modal footer with cancel and submit buttons.

  ## Examples

      <.modal_footer
        cancel_url={~p"/dashboard"}
        submit_text="Save"
        loading={false}
      />
  """
  attr :cancel_patch, :string, default: nil
  attr :cancel_click, :any, default: nil
  attr :submit_text, :string, default: "Submit"
  attr :submit_class, :string, default: "bg-green-600 hover:bg-green-700"
  attr :loading, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :loading_text, :string, default: "Processing..."
  attr :info_text, :string, default: nil
  attr :class, :string, default: nil

  def modal_footer(assigns) do
    ~H"""
    <div class={["relative pt-6 mt-6 flex items-center justify-between -mx-10 px-10", @class]}>
      <div class="absolute left-0 right-0 top-0 border-t border-slate-200"></div>
      <div :if={@info_text} class="text-xs text-slate-500">
        {@info_text}
      </div>
      <div :if={!@info_text}></div>
      <div class="flex space-x-3">
        <button
          :if={@cancel_patch}
          type="button"
          phx-click={Phoenix.LiveView.JS.patch(@cancel_patch)}
          class="px-5 py-2.5 border border-slate-300 rounded-lg shadow-sm text-sm font-medium text-hubspot-cancel bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          Cancel
        </button>
        <button
          :if={@cancel_click}
          type="button"
          phx-click={@cancel_click}
          class="px-5 py-2.5 border border-slate-300 rounded-lg shadow-sm text-sm font-medium text-hubspot-cancel bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={@loading || @disabled}
          class={
            "px-5 py-2.5 rounded-lg shadow-sm text-sm font-medium text-white " <>
              @submit_class <> " disabled:opacity-50"
          }
        >
          <span :if={@loading}>{@loading_text}</span>
          <span :if={!@loading}>{@submit_text}</span>
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty state message.

  ## Examples

      <.empty_state title="No results" message="Try a different search." />
  """
  attr :title, :string, default: nil
  attr :message, :string, required: true
  attr :submessage, :string, default: nil
  attr :class, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div class={["text-center py-8 text-slate-500", @class]}>
      <p :if={@title} class="font-medium text-slate-700 mb-1">{@title}</p>
      <p>{@message}</p>
      <p :if={@submessage} class="text-sm mt-2">{@submessage}</p>
    </div>
    """
  end

  @doc """
  Renders an error message.

  ## Examples

      <.inline_error :if={@error} message={@error} />
  """
  attr :message, :string, required: true
  attr :class, :string, default: nil

  def inline_error(assigns) do
    ~H"""
    <p class={["text-red-600 text-sm", @class]}>{@message}</p>
    """
  end
end
