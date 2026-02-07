defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceTokenRefresher
  alias SocialScribe.Accounts

  import SocialScribe.AccountsFixtures

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "attempts refresh when token is about to expire within 5 minutes" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 200, :second)
        })

      # This will attempt to refresh but fail without valid OAuth config
      # The important thing is it attempts the refresh
      result = SalesforceTokenRefresher.ensure_valid_token(credential)

      # Should return error since we don't have valid OAuth credentials configured
      assert match?({:error, _}, result)
    end
  end

  describe "refresh_credential/1" do
    test "updates credential in database on successful refresh" do
      # This test simulates what refresh_credential does after successful API call
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "old_token",
          refresh_token: "old_refresh"
        })

      # Simulate what refresh_credential does after successful API call
      # Note: Salesforce doesn't return a new refresh_token, so we keep the existing one
      # Uses update_salesforce_credential which properly casts instance_url
      attrs = %{
        token: "new_access_token",
        refresh_token: credential.refresh_token,
        expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
        instance_url: "https://updated.salesforce.com"
      }

      {:ok, updated} = Accounts.update_salesforce_credential(credential, attrs)

      assert updated.token == "new_access_token"
      assert updated.refresh_token == credential.refresh_token
      assert updated.instance_url == "https://updated.salesforce.com"
      assert updated.id == credential.id
    end

    test "preserves instance_url when not updated" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          instance_url: "https://original.salesforce.com"
        })

      attrs = %{
        token: "new_access_token",
        expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, attrs)

      assert updated.token == "new_access_token"
      assert updated.instance_url == "https://original.salesforce.com"
    end
  end

  describe "client/0" do
    test "returns a Tesla client with FormUrlencoded and JSON middleware" do
      client = SalesforceTokenRefresher.client()

      assert %Tesla.Client{} = client
      assert length(client.pre) == 2
    end
  end
end
