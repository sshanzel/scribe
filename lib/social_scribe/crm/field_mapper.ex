defmodule SocialScribe.CRM.FieldMapper do
  @moduledoc """
  Shared utility for mapping internal field names to CRM API field names.

  Used by HubSpot and Salesforce APIs to convert field names when updating contacts.
  """

  alias SocialScribe.CRM.FieldConfig

  @doc """
  Maps internal field names to CRM API field names using FieldConfig.

  ## Parameters
    - `crm` - The CRM type (:hubspot or :salesforce)
    - `updates` - Map of field names to values

  ## Examples

      iex> map_fields_for_crm(:salesforce, %{"address" => "123 Main St"})
      %{"MailingStreet" => "123 Main St"}
  """
  @spec map_fields_for_crm(FieldConfig.crm(), map()) :: map()
  def map_fields_for_crm(crm, updates) when is_map(updates) do
    config_module = FieldConfig.for_crm(crm)
    field_mapping = config_module.field_to_api_mapping()
    map_fields_to_api(updates, field_mapping)
  end

  @doc """
  Maps internal field names to CRM API field names.

  ## Parameters
    - `updates` - Map of field names to values
    - `field_mapping` - Map of internal field names to API field names

  ## Examples

      iex> mapping = %{"address" => "MailingStreet", "city" => "MailingCity"}
      iex> map_fields_to_api(%{"address" => "123 Main St"}, mapping)
      %{"MailingStreet" => "123 Main St"}
  """
  @spec map_fields_to_api(map(), map()) :: map()
  def map_fields_to_api(updates, field_mapping) when is_map(updates) do
    Map.new(updates, fn {field, value} ->
      field_str = to_string(field)
      api_field = Map.get(field_mapping, field_str, field_str)
      {api_field, value}
    end)
  end
end
