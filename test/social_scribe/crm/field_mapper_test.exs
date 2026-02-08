defmodule SocialScribe.CRM.FieldMapperTest do
  use ExUnit.Case, async: true

  alias SocialScribe.CRM.FieldMapper

  describe "map_fields_for_crm/2" do
    test "maps HubSpot fields to API names" do
      updates = %{
        "linkedin_url" => "https://linkedin.com/in/john",
        "twitter_handle" => "@johndoe",
        "firstname" => "John"
      }

      result = FieldMapper.map_fields_for_crm(:hubspot, updates)

      # Fields with api_name mapping
      assert result["hs_linkedin_url"] == "https://linkedin.com/in/john"
      assert result["twitterhandle"] == "@johndoe"
      # Fields without mapping keep original name
      assert result["firstname"] == "John"
    end

    test "maps Salesforce fields to API names" do
      updates = %{
        "firstname" => "Jane",
        "lastname" => "Doe",
        "city" => "San Francisco",
        "address" => "123 Main St"
      }

      result = FieldMapper.map_fields_for_crm(:salesforce, updates)

      assert result["FirstName"] == "Jane"
      assert result["LastName"] == "Doe"
      assert result["MailingCity"] == "San Francisco"
      assert result["MailingStreet"] == "123 Main St"
    end

    test "handles empty updates map" do
      assert FieldMapper.map_fields_for_crm(:hubspot, %{}) == %{}
      assert FieldMapper.map_fields_for_crm(:salesforce, %{}) == %{}
    end

    test "handles atom keys in updates" do
      updates = %{firstname: "John", email: "john@example.com"}

      result = FieldMapper.map_fields_for_crm(:salesforce, updates)

      assert result["FirstName"] == "John"
      assert result["Email"] == "john@example.com"
    end
  end

  describe "map_fields_to_api/2" do
    test "maps fields using provided mapping" do
      mapping = %{"old_name" => "NewName", "another" => "MappedAnother"}
      updates = %{"old_name" => "value1", "another" => "value2"}

      result = FieldMapper.map_fields_to_api(updates, mapping)

      assert result["NewName"] == "value1"
      assert result["MappedAnother"] == "value2"
    end

    test "keeps original name when no mapping exists" do
      mapping = %{"mapped_field" => "MappedField"}
      updates = %{"mapped_field" => "value1", "unmapped_field" => "value2"}

      result = FieldMapper.map_fields_to_api(updates, mapping)

      assert result["MappedField"] == "value1"
      assert result["unmapped_field"] == "value2"
    end

    test "handles empty mapping" do
      updates = %{"field1" => "value1", "field2" => "value2"}

      result = FieldMapper.map_fields_to_api(updates, %{})

      assert result["field1"] == "value1"
      assert result["field2"] == "value2"
    end

    test "converts atom keys to strings" do
      mapping = %{"field" => "MappedField"}
      updates = %{field: "value"}

      result = FieldMapper.map_fields_to_api(updates, mapping)

      assert result["MappedField"] == "value"
    end
  end
end
