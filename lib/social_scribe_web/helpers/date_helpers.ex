defmodule SocialScribeWeb.DateHelpers do
  @moduledoc """
  Helper functions for formatting dates in the user's local timezone.

  Uses Timex to convert UTC datetimes to the user's timezone before formatting.
  The timezone is detected client-side and passed via LiveSocket connect params.
  """

  @doc """
  Formats a datetime in the user's local timezone.

  ## Formats

  * `:short` - "Feb 9, 2025" (date only)
  * `:long` - "11:17am - February 9, 2025" (time and date)
  * `:datetime` - "02/09/2025, 11:17:00 AM" (full datetime)

  ## Examples

      iex> format_local_time(~U[2025-02-09 16:17:00Z], "America/New_York", :short)
      "Feb 9, 2025"

      iex> format_local_time(~U[2025-02-09 16:17:00Z], "America/New_York", :long)
      "11:17am - February 9, 2025"
  """
  @spec format_local_time(DateTime.t() | NaiveDateTime.t() | nil, String.t(), atom()) :: String.t()
  def format_local_time(datetime, timezone \\ "UTC", format \\ :short)

  def format_local_time(nil, _timezone, _format), do: ""

  def format_local_time(datetime, timezone, format) do
    datetime
    |> to_local(timezone)
    |> format_datetime(format)
  rescue
    # If timezone is invalid, fall back to UTC
    _ -> format_datetime(datetime, format)
  end

  defp to_local(%NaiveDateTime{} = dt, timezone) do
    dt
    |> DateTime.from_naive!("UTC")
    |> to_local(timezone)
  end

  defp to_local(%DateTime{} = dt, timezone) do
    case Timex.Timezone.convert(dt, timezone) do
      %DateTime{} = converted -> converted
      {:error, _} -> dt
    end
  end

  defp to_local(other, _timezone), do: other

  defp format_datetime(nil, _format), do: ""

  defp format_datetime(datetime, :short) do
    Timex.format!(datetime, "%b %-d, %Y", :strftime)
  end

  defp format_datetime(datetime, :long) do
    time = Timex.format!(datetime, "%-I:%M%P", :strftime)
    date = Timex.format!(datetime, "%B %-d, %Y", :strftime)
    "#{time} - #{date}"
  end

  defp format_datetime(datetime, :datetime) do
    Timex.format!(datetime, "%m/%d/%Y, %-I:%M:%S %p", :strftime)
  end
end
