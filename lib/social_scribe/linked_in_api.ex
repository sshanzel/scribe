defmodule SocialScribe.LinkedInApi do
  @moduledoc """
  Behaviour and facade for LinkedIn API operations.

  This module defines callbacks for posting content to LinkedIn and delegates
  to the configured implementation. Uses `SocialScribe.LinkedIn` by default
  but can be configured for testing via the `:linkedin_api` config key.

  ## Configuration

      config :social_scribe, :linkedin_api, MyMockModule
  """

  @callback post_text_share(token :: String.t(), author_urn :: String.t(), text :: String.t()) ::
              {:ok, any()} | {:error, any()}

  def post_text_share(token, author_urn, text) do
    impl().post_text_share(token, author_urn, text)
  end

  defp impl do
    Application.get_env(:social_scribe, :linkedin_api, SocialScribe.LinkedIn)
  end
end
