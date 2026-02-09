defmodule SocialScribe.Workers.HubspotTokenRefresherTest do
  use SocialScribe.DataCase, async: false

  import Mox
  import SocialScribe.AccountsFixtures

  alias SocialScribe.Workers.HubspotTokenRefresher
  alias SocialScribe.HubspotTokenRefresherMock

  setup :verify_on_exit!

  setup do
    Application.put_env(:social_scribe, :hubspot_token_refresher, HubspotTokenRefresherMock)

    on_exit(fn ->
      Application.delete_env(:social_scribe, :hubspot_token_refresher)
    end)

    :ok
  end

  describe "perform/1" do
    test "returns :ok when no hubspot credentials are expiring" do
      user = user_fixture()

      # Create a credential that expires in 30 minutes (outside 10-minute threshold)
      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
      })

      # No refresh should be called
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

      # No refresh should be called
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

      # No refresh should be called (hubspot is not expiring, salesforce is ignored)
      assert :ok = perform_job(HubspotTokenRefresher, %{})
    end

    test "refreshes credentials expiring within threshold" do
      user = user_fixture()

      # Create a credential expiring within the 10-minute threshold
      expiring_cred =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
        })

      # Create a credential outside the threshold
      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
      })

      # Mock should only be called for the expiring credential
      expect(HubspotTokenRefresherMock, :refresh_credential, fn credential ->
        assert credential.id == expiring_cred.id
        {:ok, credential}
      end)

      assert :ok = perform_job(HubspotTokenRefresher, %{})
    end

    test "handles refresh errors gracefully" do
      user = user_fixture()

      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
      })

      expect(HubspotTokenRefresherMock, :refresh_credential, fn _credential ->
        {:error, :refresh_failed}
      end)

      # Worker should still return :ok even when refresh fails
      assert :ok = perform_job(HubspotTokenRefresher, %{})
    end

    test "refreshes multiple expiring credentials" do
      user = user_fixture()

      cred1 =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3, :minute)
        })

      cred2 =
        hubspot_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
        })

      expected_ids = MapSet.new([cred1.id, cred2.id])

      expect(HubspotTokenRefresherMock, :refresh_credential, 2, fn credential ->
        assert MapSet.member?(expected_ids, credential.id)
        {:ok, credential}
      end)

      assert :ok = perform_job(HubspotTokenRefresher, %{})
    end
  end
end
