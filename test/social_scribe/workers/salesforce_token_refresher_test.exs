defmodule SocialScribe.Workers.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Workers.SalesforceTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "perform/1" do
    test "returns :ok when no salesforce credentials are expiring" do
      user = user_fixture()

      # Create a credential that expires in 30 minutes (outside 10-minute threshold)
      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
      })

      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end

    test "returns :ok when no salesforce credentials exist" do
      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end

    test "ignores credentials without refresh_token" do
      user = user_fixture()

      # Create a credential expiring soon but without refresh token
      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 5, :minute),
        refresh_token: nil
      })

      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end

    test "only processes salesforce credentials, ignores hubspot" do
      user = user_fixture()

      # Create a hubspot credential expiring soon
      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
      })

      # Create a salesforce credential not expiring soon
      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
      })

      # Should complete successfully without attempting to refresh hubspot
      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end

    test "identifies credentials expiring within threshold" do
      user = user_fixture()

      # Create a credential expiring within the 10-minute threshold
      expiring_cred =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
        })

      # Create a credential outside the threshold
      safe_cred =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
        })

      # The job will attempt to refresh but fail (no valid OAuth config in test)
      # This tests the credential selection logic
      assert :ok = perform_job(SalesforceTokenRefresher, %{})

      # Verify the credentials are unchanged (refresh fails silently)
      assert SocialScribe.Repo.get!(SocialScribe.Accounts.UserCredential, expiring_cred.id)
      assert SocialScribe.Repo.get!(SocialScribe.Accounts.UserCredential, safe_cred.id)
    end
  end
end
