defmodule SocialScribeWeb.CRM.ModalHelpers do
  @moduledoc """
  Shared helpers for CRM modal components (HubSpot, Salesforce).

  This module provides common functionality for CRM update modals:
  - Default socket assigns
  - Event handler logic
  - Utility functions

  Each CRM modal component defines its own configuration and delegates
  to these shared helpers.
  """

  import Phoenix.Component, only: [assign: 2, assign_new: 3]

  @doc """
  Default assigns for CRM modal components.
  """
  def default_assigns do
    [
      step: :search,
      query: "",
      contacts: [],
      selected_contact: nil,
      suggestions: [],
      loading: false,
      searching: false,
      dropdown_open: false,
      error: nil
    ]
  end

  @doc """
  Applies default assigns to socket using assign_new.
  """
  def apply_default_assigns(socket) do
    Enum.reduce(default_assigns(), socket, fn {key, value}, socket ->
      assign_new(socket, key, fn -> value end)
    end)
  end

  @doc """
  Standard update handler for CRM modals.

  This handles all common update logic including:
  - Applying incoming assigns
  - Selecting all suggestions by default

  ## Example

      def update(assigns, socket) do
        ModalHelpers.handle_update(socket, assigns, @crm_config)
      end
  """
  def handle_update(socket, assigns, _config) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_select_all_suggestions(assigns)

    {:ok, socket}
  end

  @doc """
  Marks all suggestions as selected by default.
  """
  def maybe_select_all_suggestions(socket, %{suggestions: suggestions})
      when is_list(suggestions) do
    assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
  end

  def maybe_select_all_suggestions(socket, _assigns), do: socket

  @doc """
  Handles contact_search event.

  ## Config
  - `:search_message` - The message atom to send for search (e.g., `:hubspot_search`)
  """
  def handle_contact_search(socket, %{"value" => query}, config) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
      send(self(), {config.search_message, query, socket.assigns.credential})
      {:noreply, socket}
    else
      {:noreply, assign(socket, query: query, contacts: [], dropdown_open: query != "")}
    end
  end

  @doc """
  Handles open_contact_dropdown event.
  """
  def handle_open_contact_dropdown(socket) do
    {:noreply, assign(socket, dropdown_open: true)}
  end

  @doc """
  Handles close_contact_dropdown event.
  """
  def handle_close_contact_dropdown(socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  @doc """
  Handles toggle_contact_dropdown event.

  ## Config
  - `:search_message` - The message atom to send for search
  """
  def handle_toggle_contact_dropdown(socket, config) do
    if socket.assigns.dropdown_open do
      {:noreply, assign(socket, dropdown_open: false)}
    else
      socket = assign(socket, dropdown_open: true, searching: true)

      query =
        "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"

      send(self(), {config.search_message, query, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @doc """
  Handles select_contact event.

  ## Config
  - `:generate_message` - The message atom to send for generating suggestions
  """
  def handle_select_contact(socket, %{"id" => contact_id}, config) do
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
        {config.generate_message, contact, socket.assigns.meeting, socket.assigns.credential}
      )

      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Contact not found")}
    end
  end

  @doc """
  Handles clear_contact event.
  """
  def handle_clear_contact(socket) do
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

  @doc """
  Handles toggle_suggestion event.
  """
  def handle_toggle_suggestion(socket, params) do
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

  @doc """
  Handles apply_updates event with selected fields.

  ## Config
  - `:apply_message` - The message atom to send for applying updates
  """
  def handle_apply_updates(socket, %{"apply" => selected, "values" => values}, config) do
    socket = assign(socket, loading: true, error: nil)

    updates =
      selected
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        Map.put(acc, field, Map.get(values, field, ""))
      end)

    send(
      self(),
      {config.apply_message, updates, socket.assigns.selected_contact, socket.assigns.credential}
    )

    {:noreply, socket}
  end

  @doc """
  Handles apply_updates event when no fields selected.
  """
  def handle_apply_updates_empty(socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end
end
