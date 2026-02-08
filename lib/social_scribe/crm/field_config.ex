defmodule SocialScribe.CRM.FieldConfig do
  @moduledoc """
  Base behaviour and macro for CRM field configurations.

  Each CRM implements its own FieldConfig module with field definitions.
  The base module provides shared utility functions via `use`.

  ## Usage

      defmodule SocialScribe.CRM.HubSpot.FieldConfig do
        use SocialScribe.CRM.FieldConfig

        @impl true
        def fields do
          [
            %{name: "firstname", label: "First Name", category: "basic"},
            %{name: "linkedin_url", label: "LinkedIn", api_name: "hs_linkedin_url", category: "online"}
          ]
        end
      end

  ## Field Structure

  Each field is a map with:
  - `:name` - Internal field name (used in AI prompts and internal code)
  - `:label` - Human-readable label for UI
  - `:api_name` - (optional) API field name if different from internal name
  - `:category` - (optional) Field category for grouping in prompts
  """

  @type field :: %{
          name: String.t(),
          label: String.t(),
          api_name: String.t() | nil,
          category: String.t() | nil
        }

  @type crm :: :hubspot | :salesforce

  @type prompt_example :: %{
          field: String.t(),
          value: String.t(),
          context: String.t()
        }

  @callback fields() :: [field()]

  @doc """
  Returns the display name for this CRM (e.g., "HubSpot", "Salesforce").
  """
  @callback display_name() :: String.t()

  @doc """
  Returns an example for the AI prompt showing field, value, and context.
  """
  @callback prompt_example() :: prompt_example()

  defmacro __using__(_opts) do
    quote do
      @behaviour SocialScribe.CRM.FieldConfig

      @doc """
      Returns a list of internal field names.
      """
      @spec field_names() :: [String.t()]
      def field_names do
        fields() |> Enum.map(& &1.name)
      end

      @doc """
      Returns a map of internal field names to human-readable labels.
      """
      @spec field_labels() :: %{String.t() => String.t()}
      def field_labels do
        fields() |> Map.new(&{&1.name, &1.label})
      end

      @doc """
      Returns a map of internal field names to API field names.
      Only includes fields where the API name differs from the internal name.
      """
      @spec field_to_api_mapping() :: %{String.t() => String.t()}
      def field_to_api_mapping do
        fields()
        |> Enum.filter(&Map.has_key?(&1, :api_name))
        |> Map.new(&{&1.name, &1.api_name})
      end

      @doc """
      Returns a list of API field names to fetch from the CRM.
      """
      @spec api_field_names() :: [String.t()]
      def api_field_names do
        fields() |> Enum.map(&(&1[:api_name] || &1.name))
      end

      @doc """
      Returns fields grouped by category.
      """
      @spec fields_by_category() :: %{String.t() => [SocialScribe.CRM.FieldConfig.field()]}
      def fields_by_category do
        fields() |> Enum.group_by(&(&1[:category] || "other"))
      end

      @doc """
      Returns a map of API field names to internal field names.
      """
      @spec api_to_field_mapping() :: %{String.t() => String.t()}
      def api_to_field_mapping do
        fields()
        |> Map.new(fn field ->
          api_name = field[:api_name] || field.name
          {api_name, field.name}
        end)
      end
    end
  end

  # =============================================================================
  # Registry - Maps CRM atoms to their FieldConfig modules
  # =============================================================================

  @doc """
  Returns the FieldConfig module for a given CRM.
  """
  @spec for_crm(crm()) :: module()
  def for_crm(:hubspot), do: SocialScribe.CRM.HubSpot.FieldConfig
  def for_crm(:salesforce), do: SocialScribe.CRM.Salesforce.FieldConfig

  @doc """
  Returns the list of supported CRMs.
  """
  @spec supported_crms() :: [crm()]
  def supported_crms, do: [:hubspot, :salesforce]
end
