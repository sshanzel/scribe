defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Refreshes Salesforce OAuth tokens.
  """

  @salesforce_token_url "https://login.salesforce.com/services/oauth2/token"

  def client do
    Tesla.client([
      {Tesla.Middleware.FormUrlencoded,
       encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1},
      Tesla.Middleware.JSON
    ])
  end

  @doc """
  Refreshes a Salesforce access token using the refresh token.
  Returns {:ok, response_body} with new access_token and other token info.
  Note: Salesforce doesn't return a new refresh_token on refresh - the original remains valid.
  """
  def refresh_token(refresh_token_string) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    client_id = config[:client_id]
    client_secret = config[:client_secret]

    body = %{
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token_string
    }

    case Tesla.post(client(), @salesforce_token_url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes the token for a Salesforce credential and updates it in the database.
  """
  def refresh_credential(credential) do
    alias SocialScribe.Accounts

    case refresh_token(credential.refresh_token) do
      {:ok, response} ->
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

        attrs = %{
          token: response["access_token"],
          # Salesforce doesn't return a new refresh_token, keep the existing one
          refresh_token: credential.refresh_token,
          expires_at: expires_at,
          # Update instance_url in case it changed
          instance_url: response["instance_url"] || credential.instance_url
        }

        Accounts.update_salesforce_credential(credential, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ensures a credential has a valid (non-expired) token.
  Refreshes if expired or about to expire (within 5 minutes).
  """
  def ensure_valid_token(credential) do
    buffer_seconds = 300

    if DateTime.compare(
         credential.expires_at,
         DateTime.add(DateTime.utc_now(), buffer_seconds, :second)
       ) == :lt do
      refresh_credential(credential)
    else
      {:ok, credential}
    end
  end
end
