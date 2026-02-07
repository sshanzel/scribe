defmodule SocialScribe.HubspotSuggestions do
  @moduledoc """
  Generates and formats HubSpot contact update suggestions by combining
  AI-extracted data with existing HubSpot contact information.

  Uses the shared CRM suggestions base with HubSpot-specific configuration.
  """

  use SocialScribe.CRMSuggestions.Base

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.HubspotApi

  @impl SocialScribe.CRMSuggestions.Base
  def field_labels do
    %{
      "firstname" => "First Name",
      "lastname" => "Last Name",
      "email" => "Email",
      "phone" => "Phone",
      "mobilephone" => "Mobile Phone",
      "company" => "Company",
      "jobtitle" => "Job Title",
      "address" => "Address",
      "city" => "City",
      "state" => "State",
      "zip" => "ZIP Code",
      "country" => "Country",
      "website" => "Website",
      "linkedin_url" => "LinkedIn",
      "twitter_handle" => "Twitter"
    }
  end

  @impl SocialScribe.CRMSuggestions.Base
  def get_contact(credential, contact_id) do
    HubspotApi.get_contact(credential, contact_id)
  end

  @impl SocialScribe.CRMSuggestions.Base
  def generate_ai_suggestions(meeting) do
    AIContentGeneratorApi.generate_hubspot_suggestions(meeting)
  end
end
