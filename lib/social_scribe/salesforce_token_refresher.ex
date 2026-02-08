defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Refreshes Salesforce OAuth tokens.

  Uses the shared token refresher base with Salesforce-specific configuration.

  Note: Salesforce doesn't return a new refresh_token on refresh - the original remains valid.
  Salesforce returns `issued_at` (Unix timestamp in milliseconds) instead of `expires_in`.
  """

  use SocialScribe.TokenRefresher.Base,
    token_url: "https://login.salesforce.com/services/oauth2/token",
    oauth_config_key: Ueberauth.Strategy.Salesforce.OAuth

  alias SocialScribe.Accounts.Credentials

  @impl SocialScribe.TokenRefresher.Base
  def parse_token_response(response, credential) do
    # Salesforce returns issued_at (Unix timestamp in milliseconds) instead of expires_in
    # Access tokens typically expire in 2 hours (7200 seconds)
    expires_at =
      case response["issued_at"] do
        issued_at when is_binary(issued_at) ->
          issued_ms = String.to_integer(issued_at)
          # Add 2 hours (default Salesforce token lifetime)
          DateTime.from_unix!(div(issued_ms, 1000) + 7200)

        _ ->
          DateTime.add(DateTime.utc_now(), 7200, :second)
      end

    %{
      token: response["access_token"],
      # Salesforce doesn't return a new refresh_token, keep the existing one
      refresh_token: credential.refresh_token,
      expires_at: expires_at,
      # Update instance_url in case it changed
      instance_url: response["instance_url"] || credential.instance_url
    }
  end

  @impl SocialScribe.TokenRefresher.Base
  def update_credential(credential, attrs) do
    Credentials.update_salesforce_credential(credential, attrs)
  end
end
