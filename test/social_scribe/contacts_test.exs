defmodule SocialScribe.ContactsTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Contacts
  alias SocialScribe.Contacts.Contact
  import SocialScribe.AccountsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.ContactsFixtures

  describe "create_contact/1" do
    test "creates a contact with valid attributes" do
      attrs = %{name: "John Doe", email: "john@example.com"}

      assert {:ok, %Contact{} = contact} = Contacts.create_contact(attrs)
      assert contact.name == "John Doe"
      assert contact.email == "john@example.com"
    end

    test "downcases email on create" do
      attrs = %{name: "John Doe", email: "JOHN@EXAMPLE.COM"}

      assert {:ok, %Contact{} = contact} = Contacts.create_contact(attrs)
      assert contact.email == "john@example.com"
    end

    test "fails with missing email" do
      attrs = %{name: "John Doe"}

      assert {:error, changeset} = Contacts.create_contact(attrs)
      assert "can't be blank" in errors_on(changeset).email
    end

    test "fails with duplicate email" do
      attrs = %{name: "John Doe", email: "john@example.com"}
      {:ok, _} = Contacts.create_contact(attrs)

      assert {:error, changeset} = Contacts.create_contact(attrs)
      assert "contact with this email already exists" in errors_on(changeset).email
    end
  end

  describe "update_contact/2" do
    test "updates a contact" do
      {:ok, contact} = Contacts.create_contact(%{name: "John", email: "john@example.com"})

      assert {:ok, updated} = Contacts.update_contact(contact, %{name: "John Doe"})
      assert updated.name == "John Doe"
    end
  end

  describe "delete_contact/1" do
    test "deletes a contact" do
      {:ok, contact} = Contacts.create_contact(%{name: "John", email: "john@example.com"})

      assert {:ok, _} = Contacts.delete_contact(contact)
      assert Contacts.get_contact(contact.id) == nil
    end
  end

  describe "get_contact!/1" do
    test "returns the contact" do
      {:ok, contact} = Contacts.create_contact(%{name: "John", email: "john@example.com"})

      assert Contacts.get_contact!(contact.id).id == contact.id
    end

    test "raises on not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Contacts.get_contact!(999_999)
      end
    end
  end

  describe "list_contacts/1" do
    test "returns contacts linked to user via calendar events" do
      %{contact: contact1, user: user} = contact_with_event_fixture(%{name: "Alice"})
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      # Create second contact linked to same user's calendar event
      {:ok, contact2} = Contacts.create_contact(%{name: "Bob", email: "bob@example.com"})

      {:ok, _} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: calendar_event.id,
          contact_id: contact2.id,
          display_name: "Bob"
        })

      contacts = Contacts.list_contacts(user)

      assert length(contacts) == 2
      ids = Enum.map(contacts, & &1.id)
      assert contact1.id in ids
      assert contact2.id in ids
    end

    test "returns empty list for user with no calendar events" do
      user = user_fixture()

      assert Contacts.list_contacts(user) == []
    end

    test "does not return contacts from other users' events" do
      user1 = user_fixture()
      user2 = user_fixture()
      %{contact: _contact} = contact_with_event_fixture(%{user: user1})

      assert Contacts.list_contacts(user2) == []
    end

    test "does not return duplicates when contact appears in multiple events" do
      user = user_fixture()
      {:ok, contact} = Contacts.create_contact(%{name: "John", email: "john@multi.com"})

      # Create two calendar events for the same user
      event1 = calendar_event_fixture(%{user_id: user.id})
      event2 = calendar_event_fixture(%{user_id: user.id})

      # Link the same contact to both events
      {:ok, _} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: event1.id,
          contact_id: contact.id,
          display_name: "John"
        })

      {:ok, _} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: event2.id,
          contact_id: contact.id,
          display_name: "John"
        })

      # Should return only 1 contact, not 2 duplicates
      contacts = Contacts.list_contacts(user)
      assert length(contacts) == 1
      assert hd(contacts).id == contact.id
    end
  end

  describe "search_contacts/2" do
    test "searches by name (case insensitive)" do
      %{contact: contact, user: user} = contact_with_event_fixture(%{name: "John Doe"})
      %{contact: _other} = contact_with_event_fixture(%{name: "Jane Smith", user: user})

      results = Contacts.search_contacts(user, "john")

      assert length(results) == 1
      assert hd(results).id == contact.id
    end

    test "searches by email (case insensitive)" do
      %{contact: contact, user: user} =
        contact_with_event_fixture(%{name: "John Doe", email: "john@acme.com"})

      %{contact: _other} =
        contact_with_event_fixture(%{name: "Jane Smith", email: "jane@other.com", user: user})

      results = Contacts.search_contacts(user, "acme")

      assert length(results) == 1
      assert hd(results).id == contact.id
    end

    test "returns partial matches" do
      %{contact: contact1, user: user} = contact_with_event_fixture(%{name: "John Doe"})
      %{contact: contact2} = contact_with_event_fixture(%{name: "Johnny Cash", user: user})

      results = Contacts.search_contacts(user, "john")

      assert length(results) == 2
      ids = Enum.map(results, & &1.id)
      assert contact1.id in ids
      assert contact2.id in ids
    end

    test "returns empty list for no matches" do
      %{user: user} = contact_with_event_fixture(%{name: "John Doe"})

      assert Contacts.search_contacts(user, "xyz") == []
    end

    test "limits results to 10" do
      user = user_fixture()

      for i <- 1..15 do
        %{contact: _} =
          contact_with_event_fixture(%{
            name: "User #{i}",
            email: "user#{i}@example.com",
            user: user
          })
      end

      results = Contacts.search_contacts(user, "user")

      assert length(results) == 10
    end
  end

  describe "get_contact_by_email/1" do
    test "returns contact by email" do
      {:ok, contact} = Contacts.create_contact(%{name: "John", email: "john@example.com"})

      result = Contacts.get_contact_by_email("john@example.com")

      assert result.id == contact.id
    end

    test "returns nil for non-existent email" do
      assert Contacts.get_contact_by_email("notfound@example.com") == nil
    end

    test "is case insensitive" do
      {:ok, contact} = Contacts.create_contact(%{name: "John", email: "john@example.com"})

      result = Contacts.get_contact_by_email("JOHN@EXAMPLE.COM")
      assert result.id == contact.id
    end
  end

  describe "find_or_create_contact/1" do
    test "creates new contact when not exists" do
      attrs = %{email: "new@example.com", name: "New User"}

      assert {:ok, contact} = Contacts.find_or_create_contact(attrs)
      assert contact.email == "new@example.com"
      assert contact.name == "New User"
    end

    test "returns existing contact when email exists" do
      {:ok, existing} = Contacts.create_contact(%{name: "John", email: "john@example.com"})

      attrs = %{email: "john@example.com", name: "Different Name"}

      assert {:ok, contact} = Contacts.find_or_create_contact(attrs)
      assert contact.id == existing.id
      assert contact.name == "John"
    end

    test "updates name if existing contact has no name" do
      {:ok, existing} = Contacts.create_contact(%{name: nil, email: "john@example.com"})

      attrs = %{email: "john@example.com", name: "John Doe"}

      assert {:ok, contact} = Contacts.find_or_create_contact(attrs)
      assert contact.id == existing.id
      assert contact.name == "John Doe"
    end

    test "works with string keys" do
      attrs = %{"email" => "new@example.com", "name" => "New User"}

      assert {:ok, contact} = Contacts.find_or_create_contact(attrs)
      assert contact.email == "new@example.com"
    end
  end

  describe "create_attendees_from_event_data/2" do
    test "creates contacts and attendee records from attendees list" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      attendees = [
        %{
          "email" => "john@example.com",
          "displayName" => "John Doe",
          "responseStatus" => "accepted"
        },
        %{
          "email" => "jane@example.com",
          "displayName" => "Jane Smith",
          "responseStatus" => "tentative"
        }
      ]

      records = Contacts.create_attendees_from_event_data(calendar_event.id, attendees)

      assert length(records) == 2

      # Verify contacts were created
      contacts = Contacts.list_contacts(user)
      assert length(contacts) == 2
      emails = Enum.map(contacts, & &1.email)
      assert "john@example.com" in emails
      assert "jane@example.com" in emails
    end

    test "skips attendees without email" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      attendees = [
        %{"email" => "john@example.com", "displayName" => "John Doe"},
        %{"displayName" => "No Email User"},
        %{"email" => nil, "displayName" => "Nil Email User"},
        %{"email" => "", "displayName" => "Empty Email User"}
      ]

      records = Contacts.create_attendees_from_event_data(calendar_event.id, attendees)

      assert length(records) == 1
    end

    test "does not duplicate existing contacts" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})
      {:ok, existing} = Contacts.create_contact(%{name: "John", email: "john@example.com"})

      attendees = [
        %{"email" => "john@example.com", "displayName" => "John Doe"},
        %{"email" => "jane@example.com", "displayName" => "Jane Smith"}
      ]

      _records = Contacts.create_attendees_from_event_data(calendar_event.id, attendees)

      # Verify the existing contact was used
      john_contact = Contacts.get_contact_by_email("john@example.com")
      assert john_contact.id == existing.id
    end

    test "works with atom keys" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      attendees = [
        %{email: "john@example.com", displayName: "John Doe"}
      ]

      records = Contacts.create_attendees_from_event_data(calendar_event.id, attendees)

      assert length(records) == 1
    end

    test "returns existing attendee when called twice for same contact/event" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})
      {:ok, contact} = Contacts.create_contact(%{name: "John", email: "john@duplicate.com"})

      # First creation
      {:ok, attendee1} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: calendar_event.id,
          contact_id: contact.id,
          display_name: "John"
        })

      # Second creation with same contact/event should return existing
      {:ok, attendee2} =
        Contacts.create_calendar_event_attendee(%{
          calendar_event_id: calendar_event.id,
          contact_id: contact.id,
          display_name: "John Updated"
        })

      # Both should have valid IDs and be the same record
      assert attendee1.id != nil
      assert attendee2.id != nil
      assert attendee1.id == attendee2.id
    end

    test "sets is_organizer flag correctly" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      attendees = [
        %{"email" => "host@example.com", "displayName" => "Host", "organizer" => true},
        %{"email" => "guest@example.com", "displayName" => "Guest", "organizer" => false}
      ]

      records = Contacts.create_attendees_from_event_data(calendar_event.id, attendees)

      host_record = Enum.find(records, fn r -> r.is_organizer end)
      guest_record = Enum.find(records, fn r -> not r.is_organizer end)

      assert host_record != nil
      assert guest_record != nil
    end
  end

  describe "sync_attendees_from_event_data/2" do
    test "removes old attendees and creates new ones" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      # Initial sync with Alice and Bob
      initial_attendees = [
        %{"email" => "alice@example.com", "displayName" => "Alice"},
        %{"email" => "bob@example.com", "displayName" => "Bob"}
      ]

      records = Contacts.sync_attendees_from_event_data(calendar_event.id, initial_attendees)
      assert length(records) == 2

      # Verify both contacts are linked
      contacts = Contacts.list_contacts(user)
      emails = Enum.map(contacts, & &1.email)
      assert "alice@example.com" in emails
      assert "bob@example.com" in emails

      # Resync with only Alice (Bob was removed from event)
      updated_attendees = [
        %{"email" => "alice@example.com", "displayName" => "Alice"}
      ]

      records = Contacts.sync_attendees_from_event_data(calendar_event.id, updated_attendees)
      assert length(records) == 1

      # Verify only Alice is linked now (Bob's attendee record was deleted)
      contacts = Contacts.list_contacts(user)
      assert length(contacts) == 1
      assert hd(contacts).email == "alice@example.com"
    end

    test "contacts are preserved even when attendee records are deleted" do
      user = user_fixture()
      calendar_event = calendar_event_fixture(%{user_id: user.id})

      # Create attendee
      attendees = [%{"email" => "preserved@example.com", "displayName" => "Preserved"}]
      Contacts.sync_attendees_from_event_data(calendar_event.id, attendees)

      # Get the contact
      contact = Contacts.get_contact_by_email("preserved@example.com")
      assert contact != nil

      # Resync with empty list (removes attendee record)
      Contacts.sync_attendees_from_event_data(calendar_event.id, [])

      # Contact should still exist in DB (just not linked to this event)
      contact_after = Contacts.get_contact_by_email("preserved@example.com")
      assert contact_after != nil
      assert contact_after.id == contact.id
    end
  end
end
