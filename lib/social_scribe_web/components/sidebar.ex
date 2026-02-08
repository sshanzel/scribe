defmodule SocialScribeWeb.Sidebar do
  use SocialScribeWeb, :html

  @doc """
  Renders a sidebar menu with active state highlighting.

  ## Examples

      <.sidebar current_path={~p"/protocols"} />
  """
  attr :base_path, :string, required: true, doc: "the base path to determine active state"
  attr :current_path, :string, required: true, doc: "the current path to determine active state"
  attr :links, :list, required: true, doc: "the list of links to display in the sidebar"
  attr :show_seed_button, :boolean, default: false, doc: "whether to show seed button (from env)"
  attr :seeded, :boolean, default: false, doc: "whether the user has already seeded data"

  slot :widget

  def sidebar(assigns) do
    ~H"""
    <div class="w-[212px] sticky bg-white text-black flex flex-col">
      <nav class="flex-1 px-2 mt-12">
        <button
          :if={@show_seed_button and not @seeded}
          phx-click="seed_data"
          phx-disable-with=""
          class="group w-full flex items-center gap-3 px-2 py-2 mb-4 text-sm rounded-lg bg-gradient-to-r from-emerald-500 to-teal-500 text-white hover:from-emerald-600 hover:to-teal-600 transition-all shadow-sm disabled:opacity-75 disabled:cursor-not-allowed"
        >
          <.icon
            name="hero-beaker"
            class="size-5 group-[.phx-click-loading]:hidden"
          />
          <.icon
            name="hero-arrow-path"
            class="size-5 hidden group-[.phx-click-loading]:block animate-spin"
          />
          <span class="group-[.phx-click-loading]:hidden">Seed your data!</span>
          <span class="hidden group-[.phx-click-loading]:inline">Seeding...</span>
        </button>

        <ul class="space-y-1">
          <li :for={{label, icon, path} <- @links}>
            <.sidebar_link
              base_path={@base_path}
              href={path}
              icon={icon}
              label={label}
              current_path={@current_path}
              path={path}
            />
          </li>
        </ul>
      </nav>

      <div :for={widget <- @widget}>
        {render_slot(widget)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a sidebar navigation link with the appropriate styling based on active state.

  ## Examples

      <.sidebar_link href="/dashboard" icon="home" label="Dashboard" current_path={@current_path} path="/dashboard" />
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :base_path, :string, required: true
  attr :current_path, :string, required: true
  attr :path, :string, required: true

  def sidebar_link(assigns) do
    active =
      if assigns.path == assigns.base_path do
        assigns.current_path == assigns.path
      else
        String.starts_with?(assigns.current_path, assigns.path)
      end

    assigns = assign(assigns, :active, active)

    ~H"""
    <.link
      navigate={@href}
      class={[
        "flex items-center gap-3 px-2 py-2 text-sm rounded border-b border-indigo-600",
        @active && "bg-indigo-600 text-white",
        !@active && "text-gray-600 hover:bg-gray-100"
      ]}
    >
      <.icon name={@icon} class="size-5" />
      {@label}
    </.link>
    """
  end
end
