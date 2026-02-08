defmodule SocialScribe.CRM.Suggestions.Base do
  @moduledoc """
  Shared behavior and functionality for CRM contact update suggestions.

  This module provides a `__using__` macro that implements common suggestion
  logic while allowing CRM-specific customization through callbacks.

  ## Usage

      defmodule MyApp.HubspotSuggestions do
        use SocialScribe.CRM.Suggestions.Base

        @impl true
        def field_labels do
          %{
            "firstname" => "First Name",
            "email" => "Email"
          }
        end

        @impl true
        def get_contact(credential, contact_id) do
          HubspotApi.get_contact(credential, contact_id)
        end

        @impl true
        def generate_ai_suggestions(meeting) do
          AIContentGeneratorApi.generate_crm_suggestions(:hubspot, meeting)
        end
      end

  ## Callbacks

  - `field_labels/0` - Returns a map of field names to human-readable labels
  - `get_contact/2` - Fetches contact from the CRM
  - `generate_ai_suggestions/1` - Generates AI suggestions for the meeting
  """

  @doc """
  Returns a map of CRM field names to human-readable labels.
  """
  @callback field_labels() :: %{String.t() => String.t()}

  @doc """
  Fetches a contact from the CRM.
  """
  @callback get_contact(credential :: struct(), contact_id :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Generates AI suggestions based on meeting data.
  """
  @callback generate_ai_suggestions(meeting :: struct()) ::
              {:ok, list(map())} | {:error, term()}

  defmacro __using__(_opts) do
    quote do
      @behaviour SocialScribe.CRM.Suggestions.Base

      alias SocialScribe.Accounts.UserCredential

      @doc """
      Generates suggested updates for a CRM contact based on a meeting transcript.

      Returns a list of suggestion maps, each containing:
      - field: the CRM field name
      - label: human-readable field label
      - current_value: the existing value in the CRM (or nil)
      - new_value: the AI-suggested value
      - context: explanation of where this was found in the transcript
      - apply: boolean indicating whether to apply this update (default true)
      """
      def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
        with {:ok, contact} <- get_contact(credential, contact_id),
             {:ok, ai_suggestions} <- generate_ai_suggestions(meeting) do
          suggestions =
            ai_suggestions
            |> Enum.map(fn suggestion ->
              field = suggestion.field
              current_value = get_contact_field(contact, field)

              %{
                field: field,
                label: Map.get(field_labels(), field, field),
                current_value: current_value,
                new_value: suggestion.value,
                context: suggestion.context,
                apply: true,
                has_change: current_value != suggestion.value
              }
            end)
            |> Enum.filter(fn s -> s.has_change end)

          {:ok, %{contact: contact, suggestions: suggestions}}
        end
      end

      @doc """
      Generates suggestions without fetching contact data.
      Useful when contact hasn't been selected yet.
      """
      def generate_suggestions_from_meeting(meeting) do
        case generate_ai_suggestions(meeting) do
          {:ok, ai_suggestions} ->
            suggestions =
              ai_suggestions
              |> Enum.map(fn suggestion ->
                %{
                  field: suggestion.field,
                  label: Map.get(field_labels(), suggestion.field, suggestion.field),
                  current_value: nil,
                  new_value: suggestion.value,
                  context: Map.get(suggestion, :context),
                  timestamp: Map.get(suggestion, :timestamp),
                  apply: true,
                  has_change: true
                }
              end)

            {:ok, suggestions}

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc """
      Merges AI suggestions with contact data to show current vs suggested values.
      """
      def merge_with_contact(suggestions, contact) when is_list(suggestions) do
        Enum.map(suggestions, fn suggestion ->
          current_value = get_contact_field(contact, suggestion.field)

          %{
            suggestion
            | current_value: current_value,
              has_change: current_value != suggestion.new_value,
              apply: true
          }
        end)
        |> Enum.filter(fn s -> s.has_change end)
      end

      defp get_contact_field(contact, field) when is_map(contact) do
        field_atom = String.to_existing_atom(field)
        Map.get(contact, field_atom)
      rescue
        ArgumentError -> nil
      end

      defp get_contact_field(_, _), do: nil

      defoverridable generate_suggestions: 3,
                     generate_suggestions_from_meeting: 1,
                     merge_with_contact: 2
    end
  end
end
