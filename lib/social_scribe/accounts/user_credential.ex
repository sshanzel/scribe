defmodule SocialScribe.Accounts.UserCredential do
  @moduledoc """
  Schema for OAuth credentials from various providers.

  Stores access tokens, refresh tokens, and provider-specific information
  for OAuth integrations like Google, LinkedIn, HubSpot, and Salesforce.

  ## Fields

  - `provider` - The OAuth provider name (e.g., "google", "hubspot")
  - `uid` - Unique identifier from the provider
  - `token` - Current access token
  - `refresh_token` - Token used to refresh the access token
  - `expires_at` - When the access token expires
  - `email` - Email address from the provider
  - `instance_url` - Salesforce-specific instance URL

  ## Associations

  - `user` - The user who owns this credential
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_credentials" do
    field :token, :string
    field :uid, :string
    field :provider, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    field :email, :string
    field :instance_url, :string

    belongs_to :user, SocialScribe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_credential, attrs) do
    user_credential
    |> cast(attrs, [:provider, :uid, :token, :refresh_token, :expires_at, :user_id, :email])
    |> validate_required([:provider, :uid, :token, :expires_at, :user_id, :email])
  end

  def linkedin_changeset(user_credential, attrs) do
    user_credential
    |> cast(attrs, [:provider, :uid, :token, :refresh_token, :expires_at, :user_id, :email])
    |> validate_required([:provider, :uid, :token, :expires_at, :user_id, :email])
  end

  def salesforce_changeset(user_credential, attrs) do
    user_credential
    |> cast(attrs, [
      :provider,
      :uid,
      :token,
      :refresh_token,
      :expires_at,
      :user_id,
      :email,
      :instance_url
    ])
    |> validate_required([:provider, :uid, :token, :expires_at, :user_id, :email, :instance_url])
  end
end
