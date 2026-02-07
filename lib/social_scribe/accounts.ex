defmodule SocialScribe.Accounts do
  @moduledoc """
  The Accounts context.

  Handles user management and authentication. For credential management,
  see `SocialScribe.Accounts.Credentials`.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias Ueberauth.Auth

  alias SocialScribe.Accounts.{User, UserToken, UserCredential, Credentials}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## User Credentials
  ## Delegated to SocialScribe.Accounts.Credentials

  defdelegate list_user_credentials(), to: Credentials
  defdelegate list_user_credentials(user, where \\ []), to: Credentials
  defdelegate get_user_credential!(id), to: Credentials
  defdelegate get_user_credential(user, provider, uid), to: Credentials
  defdelegate get_user_credential(user, provider), to: Credentials
  defdelegate get_user_linkedin_credential(user), to: Credentials
  defdelegate create_user_credential(attrs \\ %{}), to: Credentials
  defdelegate update_user_credential(user_credential, attrs), to: Credentials
  defdelegate delete_user_credential(user_credential), to: Credentials
  defdelegate change_user_credential(user_credential, attrs \\ %{}), to: Credentials

  ## OAuth

  def find_or_create_user_from_oauth(%Auth{} = auth) do
    Repo.transaction(fn ->
      user = find_or_create_user(auth.provider, auth.uid, auth.info.email)

      case Credentials.find_or_create_user_credential(user, auth) do
        {:ok, _} ->
          user

        {:error, _} ->
          Repo.rollback(:cannot_create_user_credential)
      end
    end)
  end

  defp find_or_create_user(provider, uid, email) do
    case get_user_by_oauth_uid(Atom.to_string(provider), uid) do
      %User{} = user ->
        user

      nil ->
        case get_user_by_email(email) do
          %User{} = user ->
            user

          nil ->
            %User{}
            |> User.oauth_registration_changeset(%{
              email: email
            })
            |> Repo.insert!()
        end
    end
  end

  defp get_user_by_oauth_uid(provider, uid) do
    from(c in UserCredential,
      where: c.provider == ^provider and c.uid == ^uid,
      join: u in assoc(c, :user),
      select: u
    )
    |> Repo.one()
  end

  ## OAuth Credential Management
  ## Delegated to SocialScribe.Accounts.Credentials

  defdelegate find_or_create_user_credential(user, auth), to: Credentials
  defdelegate find_or_create_hubspot_credential(user, attrs), to: Credentials
  defdelegate find_or_create_salesforce_credential(user, attrs), to: Credentials
  defdelegate get_user_hubspot_credential(user_id), to: Credentials
  defdelegate get_user_salesforce_credential(user_id), to: Credentials
  defdelegate update_salesforce_credential(credential, attrs), to: Credentials
  defdelegate update_credential_tokens(credential, tokens), to: Credentials

  ## Facebook Page Credentials
  ## Delegated to SocialScribe.Accounts.Credentials

  defdelegate list_facebook_page_credentials(), to: Credentials
  defdelegate get_facebook_page_credential!(id), to: Credentials
  defdelegate get_user_selected_facebook_page_credential(user), to: Credentials
  defdelegate create_facebook_page_credential(attrs \\ %{}), to: Credentials
  defdelegate update_facebook_page_credential(credential, attrs), to: Credentials
  defdelegate delete_facebook_page_credential(credential), to: Credentials
  defdelegate change_facebook_page_credential(credential, attrs \\ %{}), to: Credentials
  defdelegate link_facebook_page(user, user_credential, page_data), to: Credentials
  defdelegate list_linked_facebook_pages(user), to: Credentials
  defdelegate get_linked_facebook_page(user, facebook_page_id), to: Credentials
end
