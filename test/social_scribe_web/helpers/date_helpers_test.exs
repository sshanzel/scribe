defmodule SocialScribeWeb.DateHelpersTest do
  use ExUnit.Case, async: true

  alias SocialScribeWeb.DateHelpers

  describe "format_local_time/3" do
    test "returns empty string for nil datetime" do
      assert DateHelpers.format_local_time(nil, "UTC", :short) == ""
      assert DateHelpers.format_local_time(nil, "UTC", :long) == ""
      assert DateHelpers.format_local_time(nil, "UTC", :datetime) == ""
    end

    test "formats DateTime in :short format" do
      datetime = ~U[2025-02-09 16:17:00Z]

      result = DateHelpers.format_local_time(datetime, "UTC", :short)

      assert result == "Feb 9, 2025"
    end

    test "formats DateTime in :long format" do
      datetime = ~U[2025-02-09 16:17:00Z]

      result = DateHelpers.format_local_time(datetime, "UTC", :long)

      assert result == "4:17pm - February 9, 2025"
    end

    test "formats DateTime in :datetime format" do
      datetime = ~U[2025-02-09 16:17:30Z]

      result = DateHelpers.format_local_time(datetime, "UTC", :datetime)

      assert result == "02/09/2025, 4:17:30 PM"
    end

    test "converts timezone for :short format" do
      # 4:17 PM UTC = 11:17 AM EST (UTC-5)
      datetime = ~U[2025-02-09 16:17:00Z]

      result = DateHelpers.format_local_time(datetime, "America/New_York", :short)

      # Date should still be Feb 9 since time doesn't cross midnight
      assert result == "Feb 9, 2025"
    end

    test "converts timezone for :long format" do
      # 4:17 PM UTC = 11:17 AM EST (UTC-5)
      datetime = ~U[2025-02-09 16:17:00Z]

      result = DateHelpers.format_local_time(datetime, "America/New_York", :long)

      assert result == "11:17am - February 9, 2025"
    end

    test "converts timezone for :datetime format" do
      # 4:17 PM UTC = 11:17 AM EST (UTC-5)
      datetime = ~U[2025-02-09 16:17:30Z]

      result = DateHelpers.format_local_time(datetime, "America/New_York", :datetime)

      assert result == "02/09/2025, 11:17:30 AM"
    end

    test "handles timezone that crosses date boundary" do
      # 2:00 AM UTC on Feb 9 = 9:00 PM EST on Feb 8 (UTC-5)
      datetime = ~U[2025-02-09 02:00:00Z]

      result = DateHelpers.format_local_time(datetime, "America/New_York", :short)

      assert result == "Feb 8, 2025"
    end

    test "handles NaiveDateTime" do
      naive = ~N[2025-02-09 16:17:00]

      result = DateHelpers.format_local_time(naive, "UTC", :short)

      assert result == "Feb 9, 2025"
    end

    test "converts NaiveDateTime with timezone" do
      # Treats NaiveDateTime as UTC, then converts
      naive = ~N[2025-02-09 16:17:00]

      result = DateHelpers.format_local_time(naive, "America/New_York", :long)

      assert result == "11:17am - February 9, 2025"
    end

    test "falls back to UTC for invalid timezone" do
      datetime = ~U[2025-02-09 16:17:00Z]

      result = DateHelpers.format_local_time(datetime, "Invalid/Timezone", :short)

      assert result == "Feb 9, 2025"
    end

    test "defaults to UTC timezone when not provided" do
      datetime = ~U[2025-02-09 16:17:00Z]

      result = DateHelpers.format_local_time(datetime)

      assert result == "Feb 9, 2025"
    end

    test "defaults to :short format when not provided" do
      datetime = ~U[2025-02-09 16:17:00Z]

      result = DateHelpers.format_local_time(datetime, "UTC")

      assert result == "Feb 9, 2025"
    end

    test "handles various timezones" do
      datetime = ~U[2025-02-09 12:00:00Z]

      # UTC+9 (Tokyo) - should be 9:00 PM same day
      assert DateHelpers.format_local_time(datetime, "Asia/Tokyo", :long) ==
               "9:00pm - February 9, 2025"

      # UTC+0 (London in winter) - should be 12:00 PM
      assert DateHelpers.format_local_time(datetime, "Europe/London", :long) ==
               "12:00pm - February 9, 2025"

      # UTC-8 (Los Angeles) - should be 4:00 AM same day
      assert DateHelpers.format_local_time(datetime, "America/Los_Angeles", :long) ==
               "4:00am - February 9, 2025"
    end

    test "formats single-digit hours without leading zero in :long format" do
      datetime = ~U[2025-02-09 08:05:00Z]

      result = DateHelpers.format_local_time(datetime, "UTC", :long)

      assert result == "8:05am - February 9, 2025"
    end

    test "formats single-digit day without leading zero in :short format" do
      datetime = ~U[2025-02-05 12:00:00Z]

      result = DateHelpers.format_local_time(datetime, "UTC", :short)

      assert result == "Feb 5, 2025"
    end
  end
end
