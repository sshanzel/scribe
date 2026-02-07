defmodule SocialScribe.Accounts.UserCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          token: String.t() | nil,
          uid: String.t() | nil,
          provider: String.t() | nil,
          refresh_token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          email: String.t() | nil,
          instance_url: String.t() | nil,
          user_id: integer() | nil,
          user: Ecto.Association.NotLoaded.t() | map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

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
