defmodule SocialScribe.CRM.ContactSearchTest do
  use SocialScribe.DataCase, async: false

  alias SocialScribe.CRM.ContactSearch

  import SocialScribe.AccountsFixtures

  # Define mock modules at module level so they're available to async tasks
  defmodule MockHubSpotApiSuccess do
    def search_contacts(_credential, _query) do
      {:ok,
       [
         %{
           id: "12345",
           display_name: "John Doe",
           email: "john@example.com",
           company: "Acme Corp",
           jobtitle: "VP of Sales",
           firstname: "John",
           lastname: "Doe",
           phone: "555-1234"
         }
       ]}
    end
  end

  defmodule MockSalesforceApiSuccess do
    def search_contacts(_credential, _query) do
      {:ok,
       [
         %{
           id: "003ABC123",
           display_name: "Jane Smith",
           email: "jane@example.com",
           company: "Tech Inc",
           title: "CTO",
           firstname: "Jane",
           lastname: "Smith",
           phone: "555-5678"
         }
       ]}
    end
  end

  defmodule MockHubSpotApiError do
    def search_contacts(_credential, _query) do
      {:error, {:api_error, 500, "Internal Server Error"}}
    end
  end

  defmodule MockSalesforceApiError do
    def search_contacts(_credential, _query) do
      {:error, {:api_error, 500, "Internal Server Error"}}
    end
  end

  describe "search/2" do
    setup do
      on_exit(fn ->
        Application.delete_env(:social_scribe, :hubspot_api)
        Application.delete_env(:social_scribe, :salesforce_api)
      end)

      :ok
    end

    test "returns empty list when user has no CRM credentials and no local contacts" do
      user = user_fixture()

      # Now returns {:ok, []} since local contacts are always searched (even if empty)
      assert {:ok, []} = ContactSearch.search(user, "test")
    end

    test "searches HubSpot when credential exists" do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})

      Application.put_env(:social_scribe, :hubspot_api, MockHubSpotApiSuccess)

      {:ok, results} = ContactSearch.search(user, "john")

      assert length(results) == 1
      [contact] = results
      assert contact.id == "hubspot:12345"
      assert contact.source == :hubspot
      assert contact.name == "John Doe"
      assert contact.email == "john@example.com"
      assert contact.company == "Acme Corp"
      assert contact.title == "VP of Sales"
      assert is_map(contact.crm_data)
    end

    test "searches Salesforce when credential exists" do
      user = user_fixture()
      _credential = salesforce_credential_fixture(%{user_id: user.id})

      Application.put_env(:social_scribe, :salesforce_api, MockSalesforceApiSuccess)

      {:ok, results} = ContactSearch.search(user, "jane")

      assert length(results) == 1
      [contact] = results
      assert contact.id == "salesforce:003ABC123"
      assert contact.source == :salesforce
      assert contact.name == "Jane Smith"
      assert contact.email == "jane@example.com"
      assert contact.company == "Tech Inc"
      assert contact.title == "CTO"
      assert is_map(contact.crm_data)
    end

    test "merges results from both CRMs when both credentials exist" do
      user = user_fixture()
      _hubspot = hubspot_credential_fixture(%{user_id: user.id})
      _salesforce = salesforce_credential_fixture(%{user_id: user.id})

      Application.put_env(:social_scribe, :hubspot_api, MockHubSpotApiSuccess)
      Application.put_env(:social_scribe, :salesforce_api, MockSalesforceApiSuccess)

      {:ok, results} = ContactSearch.search(user, "contact")

      assert length(results) == 2
      sources = Enum.map(results, & &1.source) |> Enum.sort()
      assert sources == [:hubspot, :salesforce]
    end

    test "handles CRM API errors gracefully" do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})

      Application.put_env(:social_scribe, :hubspot_api, MockHubSpotApiError)

      # Should return empty list, not propagate error
      {:ok, results} = ContactSearch.search(user, "test")
      assert results == []
    end

    test "normalizes crm_data keys to strings" do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})

      Application.put_env(:social_scribe, :hubspot_api, MockHubSpotApiSuccess)

      {:ok, [contact]} = ContactSearch.search(user, "test")

      # All keys in crm_data should be strings
      assert Map.has_key?(contact.crm_data, "id")
      assert Map.has_key?(contact.crm_data, "email")
      assert Map.has_key?(contact.crm_data, "display_name")
    end

    test "returns crm_id as string" do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})

      Application.put_env(:social_scribe, :hubspot_api, MockHubSpotApiSuccess)

      {:ok, [contact]} = ContactSearch.search(user, "test")

      assert is_binary(contact.crm_id)
      assert contact.crm_id == "12345"
    end
  end
end
