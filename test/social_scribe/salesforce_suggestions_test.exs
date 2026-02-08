defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase

  alias SocialScribe.CRM.Salesforce.Suggestions, as: SalesforceSuggestions

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "Mentioned in call",
          apply: false,
          has_change: true
        },
        %{
          field: "company",
          label: "Company",
          current_value: nil,
          new_value: "Acme Corp",
          context: "Works at Acme",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003XXXXXXXXXXXX",
        phone: nil,
        company: "Acme Corp",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      # Only phone should remain since company already matches
      assert length(result) == 1
      assert hd(result).field == "phone"
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "email",
          label: "Email",
          current_value: nil,
          new_value: "test@example.com",
          context: "Email mentioned",
          apply: false,
          has_change: true
        }
      ]

      contact = %{
        id: "003XXXXXXXXXXXX",
        email: "test@example.com"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert result == []
    end

    test "handles empty suggestions list" do
      contact = %{id: "003XXXXXXXXXXXX", email: "test@example.com"}

      result = SalesforceSuggestions.merge_with_contact([], contact)

      assert result == []
    end

    test "sets apply to true for all merged suggestions" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "003XXXXXXXXXXXX", phone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).apply == true
    end
  end

  describe "field_labels" do
    test "common fields have human-readable labels" do
      suggestions = [
        %{
          field: "phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "003XXXXXXXXXXXX", phone: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert hd(result).label == "Phone"
    end

    test "salesforce-specific fields have correct labels" do
      suggestions = [
        %{
          field: "title",
          label: "Job Title",
          current_value: nil,
          new_value: "CEO",
          context: "test",
          apply: false,
          has_change: true
        },
        %{
          field: "department",
          label: "Department",
          current_value: nil,
          new_value: "Engineering",
          context: "test",
          apply: false,
          has_change: true
        }
      ]

      contact = %{id: "003XXXXXXXXXXXX", title: nil, department: nil}

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      assert length(result) == 2

      title_suggestion = Enum.find(result, &(&1.field == "title"))
      assert title_suggestion.label == "Job Title"

      dept_suggestion = Enum.find(result, &(&1.field == "department"))
      assert dept_suggestion.label == "Department"
    end
  end
end
