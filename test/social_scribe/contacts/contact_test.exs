defmodule SocialScribe.Contacts.ContactTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Contacts.Contact

  describe "changeset/2" do
    test "valid changeset with all fields" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com"
      }

      changeset = Contact.changeset(%Contact{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset without name" do
      attrs = %{
        email: "john@example.com"
      }

      changeset = Contact.changeset(%Contact{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without email" do
      attrs = %{
        name: "John Doe"
      }

      changeset = Contact.changeset(%Contact{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).email
    end

    test "invalid changeset with malformed email" do
      attrs = %{
        name: "John Doe",
        email: "not-an-email"
      }

      changeset = Contact.changeset(%Contact{}, attrs)
      refute changeset.valid?
      assert "must be a valid email" in errors_on(changeset).email
    end

    test "downcases email" do
      attrs = %{
        name: "John Doe",
        email: "JOHN@EXAMPLE.COM"
      }

      changeset = Contact.changeset(%Contact{}, attrs)
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :email) == "john@example.com"
    end

    test "enforces unique constraint on email" do
      attrs = %{
        name: "John Doe",
        email: "john@example.com"
      }

      {:ok, _contact} =
        %Contact{}
        |> Contact.changeset(attrs)
        |> Repo.insert()

      {:error, changeset} =
        %Contact{}
        |> Contact.changeset(attrs)
        |> Repo.insert()

      assert "contact with this email already exists" in errors_on(changeset).email
    end
  end

  describe "display_name/1" do
    test "returns name when present" do
      contact = %Contact{name: "John Doe", email: "john@example.com"}
      assert Contact.display_name(contact) == "John Doe"
    end

    test "returns email when name is nil" do
      contact = %Contact{name: nil, email: "john@example.com"}
      assert Contact.display_name(contact) == "john@example.com"
    end

    test "returns email when name is empty string" do
      contact = %Contact{name: "", email: "john@example.com"}
      assert Contact.display_name(contact) == "john@example.com"
    end
  end
end
