defmodule SocialScribe.CRM.Salesforce.FieldConfig do
  @moduledoc """
  Salesforce CRM field configuration.

  Defines the fields available for Salesforce contact records.
  Note: Company is not included as it's a relationship field (Account.Name) in Salesforce.
  """

  use SocialScribe.CRM.FieldConfig

  @impl true
  def display_name, do: "Salesforce"

  @impl true
  def prompt_example do
    %{
      field: "title",
      value: "VP of Sales",
      context: "Sarah mentioned she was promoted to VP of Sales"
    }
  end

  @impl true
  def fields do
    [
      # Basic Info
      %{name: "firstname", label: "First Name", api_name: "FirstName", category: "basic"},
      %{name: "lastname", label: "Last Name", api_name: "LastName", category: "basic"},
      %{name: "email", label: "Email", api_name: "Email", category: "basic"},

      # Phone
      %{name: "phone", label: "Phone", api_name: "Phone", category: "phone"},
      %{name: "mobilephone", label: "Mobile Phone", api_name: "MobilePhone", category: "phone"},

      # Work (no company - it's a relationship field in Salesforce)
      %{name: "title", label: "Job Title", api_name: "Title", category: "work"},
      %{name: "department", label: "Department", api_name: "Department", category: "work"},

      # Address
      %{name: "address", label: "Address", api_name: "MailingStreet", category: "address"},
      %{name: "city", label: "City", api_name: "MailingCity", category: "address"},
      %{name: "state", label: "State", api_name: "MailingState", category: "address"},
      %{name: "zip", label: "ZIP Code", api_name: "MailingPostalCode", category: "address"},
      %{name: "country", label: "Country", api_name: "MailingCountry", category: "address"}
    ]
  end
end
