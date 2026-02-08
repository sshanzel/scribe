defmodule SocialScribe.CRM.HubSpot.Suggestions do
  @moduledoc """
  Generates and formats HubSpot contact update suggestions by combining
  AI-extracted data with existing HubSpot contact information.

  Uses the shared CRM suggestions base with HubSpot-specific configuration.
  """

  use SocialScribe.CRM.Suggestions.Base

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.CRM.HubSpot.ApiBehaviour
  alias SocialScribe.CRM.HubSpot.FieldConfig

  @impl SocialScribe.CRM.Suggestions.Base
  def field_labels do
    FieldConfig.field_labels()
  end

  @impl SocialScribe.CRM.Suggestions.Base
  def get_contact(credential, contact_id) do
    ApiBehaviour.get_contact(credential, contact_id)
  end

  @impl SocialScribe.CRM.Suggestions.Base
  def generate_ai_suggestions(meeting) do
    AIContentGeneratorApi.generate_crm_suggestions(:hubspot, meeting)
  end
end
