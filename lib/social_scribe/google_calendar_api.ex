defmodule SocialScribe.GoogleCalendarApi do
  @moduledoc """
  Behaviour and facade for Google Calendar API operations.

  This module defines the callback for listing calendar events and delegates
  to the configured implementation. Uses `SocialScribe.GoogleCalendar` by default
  but can be configured for testing via the `:google_calendar_api` config key.

  ## Configuration

      config :social_scribe, :google_calendar_api, MyMockModule
  """

  @callback list_events(
              token :: String.t(),
              start_time :: DateTime.t(),
              end_time :: DateTime.t(),
              calendar_id :: String.t()
            ) :: {:ok, list(map())} | {:error, any()}

  def list_events(token, start_time, end_time, calendar_id),
    do: impl().list_events(token, start_time, end_time, calendar_id)

  defp impl,
    do: Application.get_env(:social_scribe, :google_calendar_api, SocialScribe.GoogleCalendar)
end
