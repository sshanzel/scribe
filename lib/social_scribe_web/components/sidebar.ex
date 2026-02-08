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
    assigns = assign(assigns, :on_link_click, nil)

    ~H"""
    <div class="w-[212px] sticky bg-white text-black flex flex-col">
      <.sidebar_nav
        base_path={@base_path}
        current_path={@current_path}
        links={@links}
        show_seed_button={@show_seed_button}
        seeded={@seeded}
        on_link_click={@on_link_click}
        class="mt-12"
      />

      <div :for={widget <- @widget}>
        {render_slot(widget)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a mobile sidebar drawer that slides in from the left.

  ## Examples

      <.mobile_sidebar_drawer id="mobile-sidebar" current_path={@current_path} links={@links} />
  """
  attr :id, :string, required: true, doc: "the unique id for the drawer"
  attr :base_path, :string, required: true, doc: "the base path to determine active state"
  attr :current_path, :string, required: true, doc: "the current path to determine active state"
  attr :links, :list, required: true, doc: "the list of links to display in the sidebar"
  attr :show_seed_button, :boolean, default: false, doc: "whether to show seed button (from env)"
  attr :seeded, :boolean, default: false, doc: "whether the user has already seeded data"

  def mobile_sidebar_drawer(assigns) do
    assigns = assign(assigns, :on_link_click, JS.hide(to: "##{assigns.id}"))

    ~H"""
    <div id={@id} class="hidden fixed inset-0 z-50 md:hidden">
      <!-- Backdrop -->
      <div class="fixed inset-0 bg-black/20" phx-click={JS.hide(to: "##{@id}")} />
      <!-- Drawer panel -->
      <div class="fixed inset-y-0 left-0 w-[212px] bg-white shadow-2xl animate-slide-in-left flex flex-col">
        <!-- Close button -->
        <div class="flex justify-end px-4 py-3">
          <button
            phx-click={JS.hide(to: "##{@id}")}
            class="text-slate-400 hover:text-slate-600"
            aria-label="Close menu"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>
        <!-- Navigation -->
        <.sidebar_nav
          base_path={@base_path}
          current_path={@current_path}
          links={@links}
          show_seed_button={@show_seed_button}
          seeded={@seeded}
          on_link_click={@on_link_click}
          class=""
        />
      </div>
    </div>
    """
  end

  # Private helper: shared navigation content for sidebar and mobile drawer
  attr :base_path, :string, required: true
  attr :current_path, :string, required: true
  attr :links, :list, required: true
  attr :show_seed_button, :boolean, default: false
  attr :seeded, :boolean, default: false
  attr :on_link_click, :any, default: nil
  attr :class, :string, default: ""

  defp sidebar_nav(assigns) do
    ~H"""
    <nav class={["flex-1 px-2", @class]}>
      <button
        :if={@show_seed_button and not @seeded}
        phx-click="seed_data"
        phx-disable-with=""
        class="group w-full flex items-center gap-3 px-2 py-2 mb-4 text-sm rounded-lg bg-gradient-to-r from-emerald-500 to-teal-500 text-white hover:from-emerald-600 hover:to-teal-600 transition-all shadow-sm disabled:opacity-75 disabled:cursor-not-allowed"
      >
        <.icon name="hero-beaker" class="size-5 group-[.phx-click-loading]:hidden" />
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
            on_click={@on_link_click}
          />
        </li>
      </ul>
    </nav>
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
  attr :on_click, :any, default: nil, doc: "optional JS command to run on click (e.g., close mobile drawer)"

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
      phx-click={@on_click}
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
