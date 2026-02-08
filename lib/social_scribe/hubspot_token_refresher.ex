defmodule SocialScribe.HubspotTokenRefresher do
  @moduledoc """
  Refreshes HubSpot OAuth tokens.

  Uses the shared token refresher base with HubSpot-specific configuration.
  """

  use SocialScribe.TokenRefresher.Base,
    token_url: "https://api.hubapi.com/oauth/v1/token",
    oauth_config_key: Ueberauth.Strategy.Hubspot.OAuth

  alias SocialScribe.Accounts.Credentials

  @impl SocialScribe.TokenRefresher.Base
  def parse_token_response(response, _credential) do
    %{
      token: response["access_token"],
      refresh_token: response["refresh_token"],
      expires_at: DateTime.add(DateTime.utc_now(), response["expires_in"], :second)
    }
  end

  @impl SocialScribe.TokenRefresher.Base
  def update_credential(credential, attrs) do
    Credentials.update_user_credential(credential, attrs)
  end
end
