defmodule SocialScribe.CRM.FieldConfigTest do
  use ExUnit.Case, async: true

  alias SocialScribe.CRM.FieldConfig
  alias SocialScribe.CRM.HubSpot
  alias SocialScribe.CRM.Salesforce

  # Test module to verify edge cases in the macro-generated functions
  defmodule TestFieldConfig do
    use SocialScribe.CRM.FieldConfig

    @impl true
    def display_name, do: "Test CRM"

    @impl true
    def prompt_example, do: %{field: "test", value: "value", context: "context"}

    @impl true
    def fields do
      [
        # Normal field without api_name
        %{name: "normal", label: "Normal Field", category: "basic"},
        # Field with different api_name (should be in mapping)
        %{name: "mapped", label: "Mapped Field", api_name: "MappedAPI", category: "basic"},
        # Field with api_name same as name (should NOT be in mapping - no-op)
        %{name: "same", label: "Same Field", api_name: "same", category: "basic"},
        # Field with nil api_name (should NOT be in mapping)
        %{name: "nil_api", label: "Nil API Field", api_name: nil, category: "basic"}
      ]
    end
  end

  describe "for_crm/1" do
    test "returns HubSpot.FieldConfig for :hubspot" do
      assert FieldConfig.for_crm(:hubspot) == HubSpot.FieldConfig
    end

    test "returns Salesforce.FieldConfig for :salesforce" do
      assert FieldConfig.for_crm(:salesforce) == Salesforce.FieldConfig
    end
  end

  describe "supported_crms/0" do
    test "returns list of supported CRMs" do
      assert FieldConfig.supported_crms() == [:hubspot, :salesforce]
    end
  end

  describe "HubSpot.FieldConfig" do
    test "fields/0 returns list of field definitions" do
      fields = HubSpot.FieldConfig.fields()

      assert is_list(fields)
      assert length(fields) > 0

      # Each field should have required keys
      Enum.each(fields, fn field ->
        assert Map.has_key?(field, :name)
        assert Map.has_key?(field, :label)
        assert is_binary(field.name)
        assert is_binary(field.label)
      end)
    end

    test "display_name/0 returns HubSpot" do
      assert HubSpot.FieldConfig.display_name() == "HubSpot"
    end

    test "prompt_example/0 returns valid example" do
      example = HubSpot.FieldConfig.prompt_example()

      assert Map.has_key?(example, :field)
      assert Map.has_key?(example, :value)
      assert Map.has_key?(example, :context)
      assert is_binary(example.field)
      assert is_binary(example.value)
      assert is_binary(example.context)
    end

    test "field_names/0 returns list of field name strings" do
      names = HubSpot.FieldConfig.field_names()

      assert is_list(names)
      assert "firstname" in names
      assert "email" in names
      assert "company" in names
    end

    test "field_labels/0 returns map of names to labels" do
      labels = HubSpot.FieldConfig.field_labels()

      assert is_map(labels)
      assert labels["firstname"] == "First Name"
      assert labels["email"] == "Email"
    end

    test "field_to_api_mapping/0 only includes fields with different API names" do
      mapping = HubSpot.FieldConfig.field_to_api_mapping()

      assert is_map(mapping)
      # linkedin_url maps to hs_linkedin_url
      assert mapping["linkedin_url"] == "hs_linkedin_url"
      # firstname has no api_name, should not be in mapping
      refute Map.has_key?(mapping, "firstname")
    end

    test "api_field_names/0 returns API names for fetching" do
      api_names = HubSpot.FieldConfig.api_field_names()

      assert is_list(api_names)
      # Fields without api_name use their internal name
      assert "firstname" in api_names
      # Fields with api_name use the api_name
      assert "hs_linkedin_url" in api_names
      refute "linkedin_url" in api_names
    end

    test "fields_by_category/0 groups fields by category" do
      by_category = HubSpot.FieldConfig.fields_by_category()

      assert is_map(by_category)
      assert Map.has_key?(by_category, "basic")
      assert Map.has_key?(by_category, "work")

      basic_fields = by_category["basic"]
      assert is_list(basic_fields)
      assert Enum.any?(basic_fields, &(&1.name == "firstname"))
    end

    test "api_to_field_mapping/0 returns reverse mapping" do
      mapping = HubSpot.FieldConfig.api_to_field_mapping()

      assert is_map(mapping)
      assert mapping["hs_linkedin_url"] == "linkedin_url"
      assert mapping["firstname"] == "firstname"
    end
  end

  describe "Salesforce.FieldConfig" do
    test "fields/0 returns list of field definitions" do
      fields = Salesforce.FieldConfig.fields()

      assert is_list(fields)
      assert length(fields) > 0
    end

    test "display_name/0 returns Salesforce" do
      assert Salesforce.FieldConfig.display_name() == "Salesforce"
    end

    test "prompt_example/0 returns valid example" do
      example = Salesforce.FieldConfig.prompt_example()

      assert Map.has_key?(example, :field)
      assert Map.has_key?(example, :value)
      assert Map.has_key?(example, :context)
    end

    test "field_names/0 returns list of field name strings" do
      names = Salesforce.FieldConfig.field_names()

      assert is_list(names)
      assert "firstname" in names
      assert "email" in names
      # Salesforce doesn't have company as a direct field
      refute "company" in names
    end

    test "field_to_api_mapping/0 maps to Salesforce API names" do
      mapping = Salesforce.FieldConfig.field_to_api_mapping()

      assert is_map(mapping)
      # Salesforce uses PascalCase API names
      assert mapping["firstname"] == "FirstName"
      assert mapping["email"] == "Email"
      assert mapping["city"] == "MailingCity"
    end

    test "api_field_names/0 returns Salesforce API field names" do
      api_names = Salesforce.FieldConfig.api_field_names()

      assert is_list(api_names)
      assert "FirstName" in api_names
      assert "Email" in api_names
      assert "MailingCity" in api_names
    end
  end

  describe "FieldConfig macro edge cases" do
    test "field_to_api_mapping/0 excludes fields without api_name" do
      mapping = TestFieldConfig.field_to_api_mapping()

      refute Map.has_key?(mapping, "normal")
    end

    test "field_to_api_mapping/0 includes fields with different api_name" do
      mapping = TestFieldConfig.field_to_api_mapping()

      assert mapping["mapped"] == "MappedAPI"
    end

    test "field_to_api_mapping/0 excludes fields where api_name equals name (no-op)" do
      mapping = TestFieldConfig.field_to_api_mapping()

      # "same" has api_name: "same" which equals the name - should be excluded
      refute Map.has_key?(mapping, "same")
    end

    test "field_to_api_mapping/0 excludes fields with nil api_name" do
      mapping = TestFieldConfig.field_to_api_mapping()

      # "nil_api" has api_name: nil - should be excluded
      refute Map.has_key?(mapping, "nil_api")
    end

    test "field_to_api_mapping/0 never contains nil values" do
      mapping = TestFieldConfig.field_to_api_mapping()

      Enum.each(mapping, fn {_key, value} ->
        assert is_binary(value), "Expected all values to be strings, got: #{inspect(value)}"
      end)
    end

    test "api_field_names/0 uses api_name when present, otherwise uses name" do
      api_names = TestFieldConfig.api_field_names()

      # Field without api_name uses name
      assert "normal" in api_names
      # Field with api_name uses api_name
      assert "MappedAPI" in api_names
      refute "mapped" in api_names
      # Field with nil api_name falls back to name
      assert "nil_api" in api_names
    end
  end
end
