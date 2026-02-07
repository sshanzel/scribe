defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Generates and formats Salesforce contact update suggestions by combining
  AI-extracted data with existing Salesforce contact information.

  Uses the shared CRM suggestions base with Salesforce-specific configuration.
  """

  use SocialScribe.CRMSuggestions.Base

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.SalesforceApiBehaviour

  @impl SocialScribe.CRMSuggestions.Base
  def field_labels do
    %{
      "firstname" => "First Name",
      "lastname" => "Last Name",
      "email" => "Email",
      "phone" => "Phone",
      "mobilephone" => "Mobile Phone",
      "company" => "Company",
      "title" => "Job Title",
      "department" => "Department",
      "address" => "Address",
      "city" => "City",
      "state" => "State",
      "zip" => "ZIP Code",
      "country" => "Country"
    }
  end

  @impl SocialScribe.CRMSuggestions.Base
  def get_contact(credential, contact_id) do
    SalesforceApiBehaviour.get_contact(credential, contact_id)
  end

  @impl SocialScribe.CRMSuggestions.Base
  def generate_ai_suggestions(meeting) do
    AIContentGeneratorApi.generate_salesforce_suggestions(meeting)
  end
end
