defmodule SocialScribe.TokenRefresherApi do
  @moduledoc """
  Behaviour and facade for OAuth token refresh operations.

  This module defines the callback for refreshing OAuth tokens and delegates
  to the configured implementation. Uses `SocialScribe.TokenRefresher` by default.

  ## Configuration

      config :social_scribe, :token_refresher_api, MyMockModule
  """

  @callback refresh_token(refresh_token :: String.t()) :: {:ok, map()} | {:error, any()}

  def refresh_token(refresh_token), do: impl().refresh_token(refresh_token)

  defp impl,
    do: Application.get_env(:social_scribe, :token_refresher_api, SocialScribe.TokenRefresher)
end
