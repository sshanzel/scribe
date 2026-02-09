defmodule SocialScribe.CRM.TokenRefresherBehaviour do
  @moduledoc """
  Behaviour for CRM token refresher modules.

  Defines the contract for refreshing OAuth credentials for CRM integrations.
  """

  @callback refresh_credential(credential :: struct()) :: {:ok, struct()} | {:error, term()}
end
