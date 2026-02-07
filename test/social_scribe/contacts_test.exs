defmodule SocialScribe.ContactsTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Contacts
  alias SocialScribe.Contacts.Contact
  import SocialScribe.AccountsFixtures

  describe "create_contact/2" do
    test "creates a contact with valid attributes" do
      user = user_fixture()

      attrs = %{name: "John Doe", email: "john@example.com"}

      assert {:ok, %Contact{} = contact} = Contacts.create_contact(user, attrs)
      assert contact.name == "John Doe"
      assert contact.email == "john@example.com"
      assert contact.user_id == user.id
    end

    test "creates a contact with user_id" do
      user = user_fixture()

      attrs = %{name: "John Doe", email: "john@example.com"}

      assert {:ok, %Contact{}} = Contacts.create_contact(user.id, attrs)
    end

    test "fails with missing email" do
      user = user_fixture()

      attrs = %{name: "John Doe"}

      assert {:error, changeset} = Contacts.create_contact(user, attrs)
      assert "can't be blank" in errors_on(changeset).email
    end
  end

  describe "update_contact/2" do
    test "updates a contact" do
      user = user_fixture()
      {:ok, contact} = Contacts.create_contact(user, %{name: "John", email: "john@example.com"})

      assert {:ok, updated} = Contacts.update_contact(contact, %{name: "John Doe"})
      assert updated.name == "John Doe"
    end
  end

  describe "delete_contact/1" do
    test "deletes a contact" do
      user = user_fixture()
      {:ok, contact} = Contacts.create_contact(user, %{name: "John", email: "john@example.com"})

      assert {:ok, _} = Contacts.delete_contact(contact)
      assert Contacts.get_contact(contact.id) == nil
    end
  end

  describe "get_contact!/1" do
    test "returns the contact" do
      user = user_fixture()
      {:ok, contact} = Contacts.create_contact(user, %{name: "John", email: "john@example.com"})

      assert Contacts.get_contact!(contact.id).id == contact.id
    end

    test "raises on not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Contacts.get_contact!(999_999)
      end
    end
  end

  describe "list_contacts/1" do
    test "returns all contacts for a user" do
      user = user_fixture()
      {:ok, contact1} = Contacts.create_contact(user, %{name: "Alice", email: "alice@example.com"})
      {:ok, contact2} = Contacts.create_contact(user, %{name: "Bob", email: "bob@example.com"})

      contacts = Contacts.list_contacts(user)

      assert length(contacts) == 2
      assert Enum.map(contacts, & &1.id) == [contact1.id, contact2.id]
    end

    test "returns empty list for user with no contacts" do
      user = user_fixture()

      assert Contacts.list_contacts(user) == []
    end

    test "does not return other users' contacts" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, _} = Contacts.create_contact(user1, %{name: "Alice", email: "alice@example.com"})

      assert Contacts.list_contacts(user2) == []
    end
  end

  describe "search_contacts/2" do
    test "searches by name (case insensitive)" do
      user = user_fixture()
      {:ok, contact} = Contacts.create_contact(user, %{name: "John Doe", email: "john@example.com"})
      {:ok, _} = Contacts.create_contact(user, %{name: "Jane Smith", email: "jane@example.com"})

      results = Contacts.search_contacts(user, "john")

      assert length(results) == 1
      assert hd(results).id == contact.id
    end

    test "searches by email (case insensitive)" do
      user = user_fixture()
      {:ok, contact} = Contacts.create_contact(user, %{name: "John Doe", email: "john@acme.com"})
      {:ok, _} = Contacts.create_contact(user, %{name: "Jane Smith", email: "jane@other.com"})

      results = Contacts.search_contacts(user, "acme")

      assert length(results) == 1
      assert hd(results).id == contact.id
    end

    test "returns partial matches" do
      user = user_fixture()
      {:ok, contact1} = Contacts.create_contact(user, %{name: "John Doe", email: "john@example.com"})
      {:ok, contact2} = Contacts.create_contact(user, %{name: "Johnny Cash", email: "johnny@example.com"})

      results = Contacts.search_contacts(user, "john")

      assert length(results) == 2
      ids = Enum.map(results, & &1.id)
      assert contact1.id in ids
      assert contact2.id in ids
    end

    test "returns empty list for no matches" do
      user = user_fixture()
      {:ok, _} = Contacts.create_contact(user, %{name: "John Doe", email: "john@example.com"})

      assert Contacts.search_contacts(user, "xyz") == []
    end

    test "limits results to 10" do
      user = user_fixture()

      for i <- 1..15 do
        Contacts.create_contact(user, %{name: "User #{i}", email: "user#{i}@example.com"})
      end

      results = Contacts.search_contacts(user, "user")

      assert length(results) == 10
    end
  end

  describe "get_contact_by_email/2" do
    test "returns contact by email" do
      user = user_fixture()
      {:ok, contact} = Contacts.create_contact(user, %{name: "John", email: "john@example.com"})

      result = Contacts.get_contact_by_email(user, "john@example.com")

      assert result.id == contact.id
    end

    test "returns nil for non-existent email" do
      user = user_fixture()

      assert Contacts.get_contact_by_email(user, "notfound@example.com") == nil
    end

    test "does not return other users' contacts" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, _} = Contacts.create_contact(user1, %{name: "John", email: "john@example.com"})

      assert Contacts.get_contact_by_email(user2, "john@example.com") == nil
    end
  end

  describe "find_or_create_contact/2" do
    test "creates new contact when not exists" do
      user = user_fixture()

      attrs = %{email: "new@example.com", name: "New User"}

      assert {:ok, contact} = Contacts.find_or_create_contact(user, attrs)
      assert contact.email == "new@example.com"
      assert contact.name == "New User"
    end

    test "returns existing contact when email exists" do
      user = user_fixture()
      {:ok, existing} = Contacts.create_contact(user, %{name: "John", email: "john@example.com"})

      attrs = %{email: "john@example.com", name: "Different Name"}

      assert {:ok, contact} = Contacts.find_or_create_contact(user, attrs)
      assert contact.id == existing.id
      assert contact.name == "John"
    end

    test "works with string keys" do
      user = user_fixture()

      attrs = %{"email" => "new@example.com", "name" => "New User"}

      assert {:ok, contact} = Contacts.find_or_create_contact(user, attrs)
      assert contact.email == "new@example.com"
    end
  end

  describe "create_contacts_from_attendees/2" do
    test "creates contacts from attendees list" do
      user = user_fixture()

      attendees = [
        %{"email" => "john@example.com", "name" => "John Doe"},
        %{"email" => "jane@example.com", "name" => "Jane Smith"}
      ]

      contacts = Contacts.create_contacts_from_attendees(user, attendees)

      assert length(contacts) == 2
      emails = Enum.map(contacts, & &1.email)
      assert "john@example.com" in emails
      assert "jane@example.com" in emails
    end

    test "skips attendees without email" do
      user = user_fixture()

      attendees = [
        %{"email" => "john@example.com", "name" => "John Doe"},
        %{"name" => "No Email User"},
        %{"email" => nil, "name" => "Nil Email User"},
        %{"email" => "", "name" => "Empty Email User"}
      ]

      contacts = Contacts.create_contacts_from_attendees(user, attendees)

      assert length(contacts) == 1
      assert hd(contacts).email == "john@example.com"
    end

    test "does not duplicate existing contacts" do
      user = user_fixture()
      {:ok, existing} = Contacts.create_contact(user, %{name: "John", email: "john@example.com"})

      attendees = [
        %{"email" => "john@example.com", "name" => "John Doe"},
        %{"email" => "jane@example.com", "name" => "Jane Smith"}
      ]

      contacts = Contacts.create_contacts_from_attendees(user, attendees)

      assert length(contacts) == 2

      john_contact = Enum.find(contacts, &(&1.email == "john@example.com"))
      assert john_contact.id == existing.id

      # Should still be only 2 total contacts in DB for this user
      assert length(Contacts.list_contacts(user)) == 2
    end

    test "works with atom keys" do
      user = user_fixture()

      attendees = [
        %{email: "john@example.com", name: "John Doe"}
      ]

      contacts = Contacts.create_contacts_from_attendees(user, attendees)

      assert length(contacts) == 1
      assert hd(contacts).email == "john@example.com"
    end
  end
end
