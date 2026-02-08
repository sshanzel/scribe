defmodule SocialScribe.Accounts.Credentials do
  @moduledoc """
  Handles user credential management for OAuth providers.

  This module manages:
  - User credentials (Google, LinkedIn, Facebook, HubSpot, Salesforce)
  - Facebook page credentials
  - Token management and updates
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias SocialScribe.Accounts.{UserCredential, FacebookPageCredential}
  alias Ueberauth.Auth

  # =============================================================================
  # User Credentials - Basic CRUD
  # =============================================================================

  @doc """
  Returns the list of user_credentials.
  """
  def list_user_credentials do
    Repo.all(UserCredential)
  end

  @doc """
  Lists user credentials with optional filters.
  """
  def list_user_credentials(user, where \\ []) do
    query =
      from c in UserCredential,
        where: c.user_id == ^user.id,
        where: ^where

    Repo.all(query)
  end

  @doc """
  Gets a single user_credential.

  Raises `Ecto.NoResultsError` if the User credential does not exist.
  """
  def get_user_credential!(id), do: Repo.get!(UserCredential, id)

  @doc """
  Gets a user credential by user, provider, and uid.
  """
  def get_user_credential(user, provider, uid) do
    Repo.get_by(UserCredential, user_id: user.id, provider: provider, uid: uid)
  end

  @doc """
  Gets a user credential by user and provider.
  """
  def get_user_credential(user, provider) do
    Repo.get_by(UserCredential, user_id: user.id, provider: provider)
  end

  @doc """
  Creates a user_credential.
  """
  def create_user_credential(attrs \\ %{}) do
    %UserCredential{}
    |> UserCredential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user_credential.
  """
  def update_user_credential(%UserCredential{} = user_credential, attrs) do
    user_credential
    |> UserCredential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user_credential.
  """
  def delete_user_credential(%UserCredential{} = user_credential) do
    Repo.delete(user_credential)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_credential changes.
  """
  def change_user_credential(%UserCredential{} = user_credential, attrs \\ %{}) do
    UserCredential.changeset(user_credential, attrs)
  end

  # =============================================================================
  # Provider-Specific Getters
  # =============================================================================

  @doc """
  Gets the user's LinkedIn credential if one exists.
  """
  def get_user_linkedin_credential(user) do
    Repo.get_by(UserCredential, user_id: user.id, provider: "linkedin")
  end

  @doc """
  Gets the user's latest credential for a given provider.

  If multiple credentials exist for the same provider, returns the most
  recently created one (by `inserted_at`) to ensure deterministic behavior.

  ## Parameters
    - `user_id` - The user's ID
    - `provider` - The provider name (e.g., "hubspot", "salesforce")

  ## Examples

      iex> get_user_latest_credential(user_id, "hubspot")
      %UserCredential{provider: "hubspot", ...}

      iex> get_user_latest_credential(user_id, "salesforce")
      nil
  """
  @spec get_user_latest_credential(integer(), String.t()) :: UserCredential.t() | nil
  def get_user_latest_credential(user_id, provider) when is_binary(provider) do
    UserCredential
    |> where([c], c.user_id == ^user_id and c.provider == ^provider)
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(1)
    |> Repo.one()
  end

  # =============================================================================
  # OAuth Credential Management
  # =============================================================================

  @doc """
  Finds or creates a user credential for a user.
  """
  def find_or_create_user_credential(user, %Auth{provider: provider} = auth)
      when provider in [:linkedin, :facebook] do
    case get_user_credential(user, Atom.to_string(auth.provider)) do
      nil ->
        create_user_credential(format_credential_attrs(user, auth))

      %UserCredential{} = credential ->
        update_user_credential(credential, format_credential_attrs(user, auth))
    end
  end

  def find_or_create_user_credential(user, %Auth{} = auth) do
    case get_user_credential(user, Atom.to_string(auth.provider), auth.uid) do
      nil ->
        create_user_credential(format_credential_attrs(user, auth))

      %UserCredential{} = credential ->
        update_user_credential(credential, format_credential_attrs(user, auth))
    end
  end

  @doc """
  Finds or creates a HubSpot credential for a user.
  """
  def find_or_create_hubspot_credential(user, attrs) do
    case get_user_credential(user, "hubspot", attrs.uid) do
      nil ->
        create_user_credential(attrs)

      %UserCredential{} = credential ->
        update_user_credential(credential, attrs)
    end
  end

  @doc """
  Finds or creates a Salesforce credential for a user.
  """
  def find_or_create_salesforce_credential(user, attrs) do
    case get_user_credential(user, "salesforce", attrs.uid) do
      nil ->
        %UserCredential{}
        |> UserCredential.salesforce_changeset(attrs)
        |> Repo.insert()

      %UserCredential{} = credential ->
        credential
        |> UserCredential.salesforce_changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Updates a Salesforce credential using the salesforce_changeset.
  """
  def update_salesforce_credential(%UserCredential{} = credential, attrs) do
    credential
    |> UserCredential.salesforce_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a user credential's tokens.
  """
  def update_credential_tokens(%UserCredential{} = credential, %{
        "access_token" => token,
        "expires_in" => expires_in
      }) do
    credential
    |> UserCredential.changeset(%{
      token: token,
      expires_at: DateTime.add(DateTime.utc_now(), expires_in, :second)
    })
    |> Repo.update()
  end

  # =============================================================================
  # Credential Formatting Helpers
  # =============================================================================

  @doc false
  def format_credential_attrs(user, %Auth{provider: :linkedin} = auth) do
    %{
      user_id: user.id,
      provider: to_string(auth.provider),
      uid: "urn:li:person:#{auth.extra.raw_info.user["sub"]}",
      token: auth.credentials.token,
      refresh_token: auth.credentials.token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }
  end

  def format_credential_attrs(user, %Auth{provider: :facebook} = auth) do
    %{
      user_id: user.id,
      provider: to_string(auth.provider),
      uid: auth.uid,
      token: auth.credentials.token,
      refresh_token: auth.credentials.token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }
  end

  def format_credential_attrs(user, %Auth{credentials: %{refresh_token: nil}} = auth) do
    %{
      user_id: user.id,
      provider: to_string(auth.provider),
      uid: auth.uid,
      token: auth.credentials.token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }
  end

  def format_credential_attrs(user, %Auth{} = auth) do
    %{
      user_id: user.id,
      provider: to_string(auth.provider),
      uid: auth.uid,
      token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }
  end

  # =============================================================================
  # Facebook Page Credentials
  # =============================================================================

  @doc """
  Returns the list of facebook_page_credentials.
  """
  def list_facebook_page_credentials do
    Repo.all(FacebookPageCredential)
  end

  @doc """
  Gets a single facebook_page_credential.

  Raises `Ecto.NoResultsError` if the Facebook page credential does not exist.
  """
  def get_facebook_page_credential!(id), do: Repo.get!(FacebookPageCredential, id)

  @doc """
  Gets the user's selected Facebook page credential.
  """
  def get_user_selected_facebook_page_credential(user) do
    Repo.get_by(FacebookPageCredential, user_id: user.id, selected: true)
  end

  @doc """
  Creates a facebook_page_credential.
  """
  def create_facebook_page_credential(attrs \\ %{}) do
    %FacebookPageCredential{}
    |> FacebookPageCredential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a facebook_page_credential.
  """
  def update_facebook_page_credential(%FacebookPageCredential{} = credential, attrs) do
    credential
    |> FacebookPageCredential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a facebook_page_credential.
  """
  def delete_facebook_page_credential(%FacebookPageCredential{} = credential) do
    Repo.delete(credential)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking facebook_page_credential changes.
  """
  def change_facebook_page_credential(%FacebookPageCredential{} = credential, attrs \\ %{}) do
    FacebookPageCredential.changeset(credential, attrs)
  end

  @doc """
  Creates or updates a FacebookPageCredential record.
  """
  def link_facebook_page(user, user_credential, page_data) do
    attrs = %{
      user_id: user.id,
      user_credential_id: user_credential.id,
      facebook_page_id: page_data.id,
      page_name: page_data.name,
      page_access_token: page_data.page_access_token,
      category: page_data.category
    }

    case get_linked_facebook_page(user, page_data.id) do
      nil ->
        create_facebook_page_credential(attrs)

      existing_credential ->
        update_facebook_page_credential(existing_credential, attrs)
    end
  end

  @doc """
  Gets all linked Facebook Pages for a user.
  """
  def list_linked_facebook_pages(user) do
    Repo.all(from fpc in FacebookPageCredential, where: fpc.user_id == ^user.id)
  end

  @doc """
  Gets a specific linked Facebook Page for a user.
  """
  def get_linked_facebook_page(user, facebook_page_id) do
    Repo.get_by(FacebookPageCredential, user_id: user.id, facebook_page_id: facebook_page_id)
  end
end
