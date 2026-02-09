defmodule SocialScribe.Workers.HubspotTokenRefresher do
  @moduledoc """
  Oban worker that proactively refreshes HubSpot OAuth tokens before they expire.
  Runs every 5 minutes and refreshes tokens expiring within 10 minutes.
  """

  use SocialScribe.Workers.TokenRefresher.Base,
    crm: "hubspot",
    refresher: SocialScribe.CRM.HubSpot.TokenRefresher,
    config_key: :hubspot_token_refresher
end
