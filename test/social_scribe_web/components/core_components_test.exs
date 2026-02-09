defmodule SocialScribeWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import SocialScribeWeb.CoreComponents

  describe "local_time/1" do
    test "renders time element with datetime attribute" do
      assigns = %{
        datetime: ~U[2025-02-09 16:17:00Z],
        timezone: "UTC",
        format: :short
      }

      html = rendered_to_string(~H"<.local_time datetime={@datetime} timezone={@timezone} />")

      assert html =~ "<time"
      assert html =~ "datetime=\"2025-02-09T16:17:00Z\""
      assert html =~ "Feb 9, 2025"
    end

    test "formats in :short format by default" do
      assigns = %{
        datetime: ~U[2025-02-09 16:17:00Z],
        timezone: "UTC"
      }

      html = rendered_to_string(~H"<.local_time datetime={@datetime} timezone={@timezone} />")

      assert html =~ "Feb 9, 2025"
    end

    test "formats in :long format when specified" do
      assigns = %{
        datetime: ~U[2025-02-09 16:17:00Z],
        timezone: "UTC"
      }

      html =
        rendered_to_string(
          ~H"<.local_time datetime={@datetime} timezone={@timezone} format={:long} />"
        )

      assert html =~ "4:17pm - February 9, 2025"
    end

    test "formats in :datetime format when specified" do
      assigns = %{
        datetime: ~U[2025-02-09 16:17:30Z],
        timezone: "UTC"
      }

      html =
        rendered_to_string(
          ~H"<.local_time datetime={@datetime} timezone={@timezone} format={:datetime} />"
        )

      assert html =~ "02/09/2025, 4:17:30 PM"
    end

    test "converts to specified timezone" do
      assigns = %{
        datetime: ~U[2025-02-09 16:17:00Z],
        timezone: "America/New_York"
      }

      html =
        rendered_to_string(
          ~H"<.local_time datetime={@datetime} timezone={@timezone} format={:long} />"
        )

      # 4:17 PM UTC = 11:17 AM EST
      assert html =~ "11:17am - February 9, 2025"
    end

    test "applies custom class" do
      assigns = %{
        datetime: ~U[2025-02-09 16:17:00Z],
        timezone: "UTC"
      }

      html =
        rendered_to_string(
          ~H"<.local_time datetime={@datetime} timezone={@timezone} class=\"text-sm text-gray-500\" />"
        )

      assert html =~ "class=\"text-sm text-gray-500\""
    end

    test "handles nil datetime" do
      assigns = %{
        datetime: nil,
        timezone: "UTC"
      }

      html = rendered_to_string(~H"<.local_time datetime={@datetime} timezone={@timezone} />")

      assert html =~ "<time"
      # Should be empty content
      refute html =~ "Feb"
    end

    test "handles NaiveDateTime" do
      assigns = %{
        datetime: ~N[2025-02-09 16:17:00],
        timezone: "UTC"
      }

      html = rendered_to_string(~H"<.local_time datetime={@datetime} timezone={@timezone} />")

      assert html =~ "Feb 9, 2025"
    end

    test "defaults timezone to UTC when not provided" do
      assigns = %{
        datetime: ~U[2025-02-09 16:17:00Z]
      }

      html = rendered_to_string(~H"<.local_time datetime={@datetime} />")

      assert html =~ "Feb 9, 2025"
    end
  end
end
