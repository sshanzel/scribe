defmodule SocialScribeWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use SocialScribeWeb, :html

  embed_templates "error_html/*"

  # Fallback for any other error status codes
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
