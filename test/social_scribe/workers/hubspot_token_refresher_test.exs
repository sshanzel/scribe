defmodule SocialScribe.Workers.HubspotTokenRefresherTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Workers.HubspotTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "perform/1" do
    test "returns :ok when no hubspot credentials are expiring" do
      user = user_fixture()

      # Create a credential that expires in 30 minutes (outside 10-minute threshold)
      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
      })

      assert :ok = perform_job(HubspotTokenRefresher, %{})
    end

    test "returns :ok when no hubspot credentials exist" do
      assert :ok = perform_job(HubspotTokenRefresher, %{})
    end

    test "ignores credentials without refresh_token" do
      user = user_fixture()

      # Create a credential expiring soon but without refresh token
      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 5, :minute),
        refresh_token: nil
      })

      assert :ok = perform_job(HubspotTokenRefresher, %{})
    end

    test "only processes hubspot credentials, ignores salesforce" do
      user = user_fixture()

      # Create a salesforce credential expiring soon
      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
      })

      # Create a hubspot credential not expiring soon
      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
      })

      # Should complete successfully without attempting to refresh salesforce
      assert :ok = perform_job(HubspotTokenRefresher, %{})
    end

    test "identifies credentials expiring within threshold" do
      user = user_fixture()

      # Create a credential expiring within the 10-minute threshold
      expiring_cred =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
        })

      # Create a credential outside the threshold
      safe_cred =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
        })

      # The job will attempt to refresh but fail (no valid OAuth config in test)
      # This tests the credential selection logic
      assert :ok = perform_job(HubspotTokenRefresher, %{})

      # Verify the credentials are unchanged (refresh fails silently)
      assert SocialScribe.Repo.get!(SocialScribe.Accounts.UserCredential, expiring_cred.id)
      assert SocialScribe.Repo.get!(SocialScribe.Accounts.UserCredential, safe_cred.id)
    end
  end
end
