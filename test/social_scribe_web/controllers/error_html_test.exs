defmodule SocialScribeWeb.ErrorHTMLTest do
  use SocialScribeWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html" do
    html = render_to_string(SocialScribeWeb.ErrorHTML, "404", "html", [])
    assert html =~ "404"
    assert html =~ "Page not found"
    assert html =~ "Go back home"
  end

  test "renders 500.html" do
    html = render_to_string(SocialScribeWeb.ErrorHTML, "500", "html", [])
    assert html =~ "500"
    assert html =~ "Something went wrong"
    assert html =~ "Go back home"
  end
end
