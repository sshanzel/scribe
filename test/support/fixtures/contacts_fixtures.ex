defmodule SocialScribe.ContactsFixtures do
  @moduledoc """
  Fixtures for creating contacts in tests.
  """

  alias SocialScribe.Contacts

  def contact_fixture(attrs \\ %{}) do
    user =
      attrs[:user] ||
        attrs[:user_id] ||
        SocialScribe.AccountsFixtures.user_fixture()

    user_id = if is_map(user), do: user.id, else: user

    {:ok, contact} =
      Contacts.create_contact(user_id, %{
        name: attrs[:name] || "John Doe",
        email: attrs[:email] || "john#{System.unique_integer([:positive])}@example.com"
      })

    contact
  end
end
