defmodule SocialScribe.CRM.FieldMapper do
  @moduledoc """
  Shared utility for mapping internal field names to CRM API field names.

  Used by HubSpot and Salesforce APIs to convert field names when updating contacts.
  """

  @doc """
  Maps internal field names to CRM API field names.

  ## Parameters
    - `updates` - Map of field names to values
    - `field_mapping` - Map of internal field names to API field names
    - `opts` - Options:
      - `:readonly_fields` - List of field names to exclude (default: [])

  ## Examples

      iex> mapping = %{"address" => "MailingStreet", "city" => "MailingCity"}
      iex> map_fields_to_api(%{"address" => "123 Main St"}, mapping)
      %{"MailingStreet" => "123 Main St"}

      iex> map_fields_to_api(%{"company" => "Acme"}, %{}, readonly_fields: ["company"])
      %{}
  """
  @spec map_fields_to_api(map(), map(), keyword()) :: map()
  def map_fields_to_api(updates, field_mapping, opts \\ []) when is_map(updates) do
    readonly_fields = Keyword.get(opts, :readonly_fields, [])

    updates
    |> Enum.reject(fn {field, _value} -> to_string(field) in readonly_fields end)
    |> Map.new(fn {field, value} ->
      field_str = to_string(field)
      api_field = Map.get(field_mapping, field_str, field_str)
      {api_field, value}
    end)
  end
end
