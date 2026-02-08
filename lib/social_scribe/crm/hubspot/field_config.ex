defmodule SocialScribe.CRM.HubSpot.FieldConfig do
  @moduledoc """
  HubSpot CRM field configuration.

  Defines the fields available for HubSpot contact records.
  """

  use SocialScribe.CRM.FieldConfig

  @impl true
  def display_name, do: "HubSpot"

  @impl true
  def prompt_example do
    %{
      field: "company",
      value: "Acme Corp",
      context: "Sarah said she just joined Acme Corp"
    }
  end

  @impl true
  def fields do
    [
      # Basic Info
      %{name: "firstname", label: "First Name", category: "basic"},
      %{name: "lastname", label: "Last Name", category: "basic"},
      %{name: "email", label: "Email", category: "basic"},

      # Phone
      %{name: "phone", label: "Phone", category: "phone"},
      %{name: "mobilephone", label: "Mobile Phone", category: "phone"},

      # Work
      %{name: "company", label: "Company", category: "work"},
      %{name: "jobtitle", label: "Job Title", category: "work"},

      # Address
      %{name: "address", label: "Address", category: "address"},
      %{name: "city", label: "City", category: "address"},
      %{name: "state", label: "State", category: "address"},
      %{name: "zip", label: "ZIP Code", category: "address"},
      %{name: "country", label: "Country", category: "address"},

      # Online
      %{name: "website", label: "Website", category: "online"},
      %{name: "linkedin_url", label: "LinkedIn", api_name: "hs_linkedin_url", category: "online"},
      %{name: "twitter_handle", label: "Twitter", api_name: "twitterhandle", category: "online"}
    ]
  end
end
