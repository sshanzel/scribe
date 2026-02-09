defmodule SocialScribe.Workers.SalesforceTokenRefresher do
  @moduledoc """
  Oban worker that proactively refreshes Salesforce OAuth tokens before they expire.
  Runs every 5 minutes and refreshes tokens expiring within 10 minutes.
  """

  use SocialScribe.Workers.TokenRefresher.Base,
    crm: "salesforce",
    refresher: SocialScribe.CRM.Salesforce.TokenRefresher,
    config_key: :salesforce_token_refresher
end
