defmodule SocialScribe.Workers.TokenRefresher.Base do
  @moduledoc """
  Base module for CRM token refresher Oban workers.

  Provides shared functionality for proactively refreshing OAuth tokens
  before they expire. Each CRM implements a slim worker using this base.

  ## Usage

      defmodule SocialScribe.Workers.HubspotTokenRefresher do
        use SocialScribe.Workers.TokenRefresher.Base,
          crm: "hubspot",
          refresher: SocialScribe.CRM.HubSpot.TokenRefresher
      end

  ## Options

  - `:crm` - The provider name (must match `user_credentials.provider`)
  - `:refresher` - The TokenRefresher module with `refresh_credential/1`
  - `:threshold_minutes` - Minutes before expiry to refresh (default: 10)
  """

  defmacro __using__(opts) do
    crm = Keyword.fetch!(opts, :crm)
    refresher = Keyword.fetch!(opts, :refresher)
    threshold = Keyword.get(opts, :threshold_minutes, 10)

    quote do
      use Oban.Worker, queue: :default, max_attempts: 3

      alias SocialScribe.Accounts.UserCredential
      alias SocialScribe.Repo

      import Ecto.Query

      require Logger

      @crm unquote(crm)
      @refresher unquote(refresher)
      @threshold_minutes unquote(threshold)

      @impl Oban.Worker
      def perform(_job) do
        Logger.info("Running proactive #{@crm} token refresh check...")

        credentials = get_expiring_credentials()

        case credentials do
          [] ->
            Logger.debug("No #{@crm} tokens expiring soon")
            :ok

          _ ->
            Logger.info("Found #{length(credentials)} #{@crm} token(s) expiring, refreshing...")
            refresh_all(credentials)
        end
      end

      defp get_expiring_credentials do
        threshold = DateTime.add(DateTime.utc_now(), @threshold_minutes, :minute)

        from(c in UserCredential,
          where: c.provider == @crm,
          where: c.expires_at < ^threshold,
          where: not is_nil(c.refresh_token)
        )
        |> Repo.all()
      end

      defp refresh_all(credentials) do
        Enum.each(credentials, fn credential ->
          case @refresher.refresh_credential(credential) do
            {:ok, _updated} ->
              Logger.info("Proactively refreshed #{@crm} token for credential #{credential.id}")

            {:error, reason} ->
              Logger.error(
                "Failed to refresh #{@crm} token for credential #{credential.id}: #{inspect(reason)}"
              )
          end
        end)

        :ok
      end

      defoverridable perform: 1, get_expiring_credentials: 0, refresh_all: 1
    end
  end
end
