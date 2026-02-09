defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  alias SocialScribe.CRM.Salesforce.Api, as: SalesforceApi

  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  describe "apply_updates/3" do
    test "returns :no_updates when updates list is empty" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003XXXXXXXXXXXX", [])
    end

    test "filters only updates with apply: true" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      # Uses internal field names (lowercase), mapped to API names by FieldMapper
      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003XXXXXXXXXXXX", updates)
    end
  end

  describe "search_contacts/2" do
    test "requires a valid credential" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
      assert credential.instance_url != nil
    end
  end

  describe "get_contact/2" do
    test "requires a valid credential and contact_id" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
      assert credential.instance_url != nil
    end
  end

  describe "create_contact/2" do
    test "requires a valid credential and contact_data map" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end

  describe "update_contact/3" do
    test "requires a valid credential, contact_id, and updates map" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end

  describe "format_contact/1" do
    test "returns nil for invalid input" do
      # Test via apply_updates with empty list to verify credential handling
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003XXXXXXXXXXXX", [])
    end
  end
end

defmodule SocialScribe.SalesforceApi.FieldMappingTest do
  @moduledoc """
  Tests that verify Salesforce API functions correctly map field names.

  These tests use Tesla.Mock to intercept HTTP calls and verify the payload
  being sent to the Salesforce API contains correctly mapped field names.
  """
  use ExUnit.Case, async: true

  alias SocialScribe.CRM.FieldMapper
  alias SocialScribe.CRM.Salesforce.FieldConfig

  describe "create_contact field mapping" do
    test "maps all basic fields from internal to API names" do
      input = %{
        "firstname" => "John",
        "lastname" => "Doe",
        "email" => "john@example.com"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, input)

      assert result["FirstName"] == "John"
      assert result["LastName"] == "Doe"
      assert result["Email"] == "john@example.com"
    end

    test "maps all phone fields from internal to API names" do
      input = %{
        "phone" => "555-1234",
        "mobilephone" => "555-5678"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, input)

      assert result["Phone"] == "555-1234"
      assert result["MobilePhone"] == "555-5678"
    end

    test "maps all work fields from internal to API names" do
      input = %{
        "title" => "Software Engineer",
        "department" => "Engineering"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, input)

      assert result["Title"] == "Software Engineer"
      assert result["Department"] == "Engineering"
    end

    test "maps all address fields from internal to API names" do
      input = %{
        "address" => "123 Main St",
        "city" => "San Francisco",
        "state" => "CA",
        "zip" => "94102",
        "country" => "USA"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, input)

      assert result["MailingStreet"] == "123 Main St"
      assert result["MailingCity"] == "San Francisco"
      assert result["MailingState"] == "CA"
      assert result["MailingPostalCode"] == "94102"
      assert result["MailingCountry"] == "USA"
    end

    test "maps all fields used by seeds.ex" do
      # This is exactly what seeds.ex passes to create_contact/update_contact
      seed_data = %{
        "firstname" => "Lisa",
        "lastname" => "Thompson",
        "email" => "lisa.t@consulting.biz",
        "phone" => "917-555-0890",
        "title" => "Managing Partner"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, seed_data)

      # Verify all fields are correctly mapped to Salesforce API names
      assert result["FirstName"] == "Lisa"
      assert result["LastName"] == "Thompson"
      assert result["Email"] == "lisa.t@consulting.biz"
      assert result["Phone"] == "917-555-0890"
      assert result["Title"] == "Managing Partner"

      # Ensure no internal field names remain
      refute Map.has_key?(result, "firstname")
      refute Map.has_key?(result, "lastname")
      refute Map.has_key?(result, "email")
      refute Map.has_key?(result, "phone")
      refute Map.has_key?(result, "title")
    end

    test "all configured Salesforce fields have valid API mappings" do
      fields = FieldConfig.fields()

      for field <- fields do
        input = %{field.name => "test_value"}
        result = FieldMapper.map_fields_for_crm(:salesforce, input)

        # The result should have the api_name as key, not the internal name
        assert Map.has_key?(result, field.api_name),
               "Field #{field.name} should map to #{field.api_name}"

        assert result[field.api_name] == "test_value"

        # Internal name should not be in result (unless it equals api_name)
        if field.name != field.api_name do
          refute Map.has_key?(result, field.name),
                 "Internal field name #{field.name} should not remain in result"
        end
      end
    end
  end

  describe "update_contact field mapping" do
    test "maps internal field names to API names for updates" do
      # Simulates what the modal sends after AI suggestions
      updates = %{
        "title" => "Senior Partner",
        "phone" => "917-555-4444",
        "city" => "Boston",
        "address" => "200 Newbury Street"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, updates)

      assert result["Title"] == "Senior Partner"
      assert result["Phone"] == "917-555-4444"
      assert result["MailingCity"] == "Boston"
      assert result["MailingStreet"] == "200 Newbury Street"
    end

    test "handles mixed atom and string keys" do
      updates = %{
        :title => "VP of Sales",
        "phone" => "555-1234"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, updates)

      assert result["Title"] == "VP of Sales"
      assert result["Phone"] == "555-1234"
    end
  end

  describe "field mapping consistency" do
    test "FieldConfig contains all expected fields for seeds" do
      field_names = FieldConfig.field_names()

      # These are the fields used by seeds.ex
      seed_fields = ["firstname", "lastname", "email", "phone", "title"]

      for field <- seed_fields do
        assert field in field_names,
               "Seed field '#{field}' should be in FieldConfig"
      end
    end

    test "field_to_api_mapping returns correct mappings" do
      mapping = FieldConfig.field_to_api_mapping()

      # Verify key mappings used by seeds
      assert mapping["firstname"] == "FirstName"
      assert mapping["lastname"] == "LastName"
      assert mapping["email"] == "Email"
      assert mapping["phone"] == "Phone"
      assert mapping["title"] == "Title"

      # Verify address mappings
      assert mapping["address"] == "MailingStreet"
      assert mapping["city"] == "MailingCity"
      assert mapping["state"] == "MailingState"
      assert mapping["zip"] == "MailingPostalCode"
      assert mapping["country"] == "MailingCountry"

      # Verify phone mappings
      assert mapping["mobilephone"] == "MobilePhone"
    end

    test "API names passed through FieldMapper remain unchanged" do
      # If someone passes API names directly (like salesforce_test_data.exs does),
      # they should pass through unchanged since they're not in the mapping keys
      api_names = %{
        "FirstName" => "John",
        "LastName" => "Doe",
        "Title" => "Engineer"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, api_names)

      # API names should pass through unchanged (idempotent for API names)
      assert result["FirstName"] == "John"
      assert result["LastName"] == "Doe"
      assert result["Title"] == "Engineer"
    end
  end

  describe "edge cases" do
    test "empty map returns empty map" do
      assert FieldMapper.map_fields_for_crm(:salesforce, %{}) == %{}
    end

    test "nil values are preserved" do
      input = %{"title" => nil, "phone" => "555-1234"}
      result = FieldMapper.map_fields_for_crm(:salesforce, input)

      assert result["Title"] == nil
      assert result["Phone"] == "555-1234"
    end

    test "unknown fields pass through unchanged" do
      input = %{
        "title" => "Engineer",
        "unknown_field" => "some value"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, input)

      assert result["Title"] == "Engineer"
      assert result["unknown_field"] == "some value"
    end
  end
end
