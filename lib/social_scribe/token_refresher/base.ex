defmodule SocialScribe.TokenRefresher.Base do
  @moduledoc """
  Shared behavior and functionality for OAuth token refreshers.

  This module provides a `__using__` macro that implements common token refresh
  logic while allowing CRM-specific customization through callbacks.

  ## Usage

      defmodule MyTokenRefresher do
        use SocialScribe.TokenRefresher.Base,
          token_url: "https://api.example.com/oauth/token",
          oauth_config_key: Ueberauth.Strategy.Example.OAuth

        @impl true
        def parse_token_response(response, _credential) do
          %{
            token: response["access_token"],
            refresh_token: response["refresh_token"],
            expires_at: DateTime.add(DateTime.utc_now(), response["expires_in"], :second)
          }
        end

        @impl true
        def update_credential(credential, attrs) do
          Accounts.update_user_credential(credential, attrs)
        end
      end

  ## Callbacks

  - `parse_token_response/2` - Parse the OAuth response into credential attrs
  - `update_credential/2` - Update the credential in the database
  """

  @doc """
  Parses the token refresh response into credential attributes.
  """
  @callback parse_token_response(response :: map(), credential :: struct()) :: map()

  @doc """
  Updates the credential in the database with new token attributes.
  """
  @callback update_credential(credential :: struct(), attrs :: map()) ::
              {:ok, struct()} | {:error, term()}

  defmacro __using__(opts) do
    token_url = Keyword.fetch!(opts, :token_url)
    oauth_config_key = Keyword.fetch!(opts, :oauth_config_key)

    quote do
      @behaviour SocialScribe.TokenRefresher.Base

      @token_url unquote(token_url)
      @oauth_config_key unquote(oauth_config_key)
      @buffer_seconds 300

      @doc """
      Returns the Tesla client for making HTTP requests.
      """
      def client do
        Tesla.client([
          {Tesla.Middleware.FormUrlencoded,
           encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1},
          Tesla.Middleware.JSON
        ])
      end

      @doc """
      Refreshes an access token using the refresh token.
      Returns {:ok, response_body} or {:error, reason}.
      """
      def refresh_token(refresh_token_string) do
        config = Application.get_env(:ueberauth, @oauth_config_key, [])
        client_id = config[:client_id]
        client_secret = config[:client_secret]

        body = %{
          grant_type: "refresh_token",
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: refresh_token_string
        }

        case Tesla.post(client(), @token_url, body) do
          {:ok, %Tesla.Env{status: 200, body: response_body}} ->
            {:ok, response_body}

          {:ok, %Tesla.Env{status: status, body: error_body}} ->
            {:error, {status, error_body}}

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc """
      Refreshes the token for a credential and updates it in the database.
      """
      def refresh_credential(credential) do
        case refresh_token(credential.refresh_token) do
          {:ok, response} ->
            attrs = parse_token_response(response, credential)
            update_credential(credential, attrs)

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc """
      Ensures a credential has a valid (non-expired) token.
      Refreshes if expired or about to expire (within 5 minutes).
      """
      def ensure_valid_token(credential) do
        if DateTime.compare(
             credential.expires_at,
             DateTime.add(DateTime.utc_now(), @buffer_seconds, :second)
           ) == :lt do
          refresh_credential(credential)
        else
          {:ok, credential}
        end
      end

      defoverridable client: 0, refresh_token: 1, refresh_credential: 1, ensure_valid_token: 1
    end
  end
end
