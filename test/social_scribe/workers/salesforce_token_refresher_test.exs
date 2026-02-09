defmodule SocialScribe.Workers.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase, async: false

  import Mox
  import SocialScribe.AccountsFixtures

  alias SocialScribe.Workers.SalesforceTokenRefresher
  alias SocialScribe.SalesforceTokenRefresherMock

  setup :verify_on_exit!

  setup do
    Application.put_env(:social_scribe, :salesforce_token_refresher, SalesforceTokenRefresherMock)

    on_exit(fn ->
      Application.delete_env(:social_scribe, :salesforce_token_refresher)
    end)

    :ok
  end

  describe "perform/1" do
    test "returns :ok when no salesforce credentials are expiring" do
      user = user_fixture()

      # Create a credential that expires in 30 minutes (outside 10-minute threshold)
      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
      })

      # No refresh should be called
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

      # No refresh should be called
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

      # No refresh should be called (salesforce is not expiring, hubspot is ignored)
      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end

    test "refreshes credentials expiring within threshold" do
      user = user_fixture()

      # Create a credential expiring within the 10-minute threshold
      expiring_cred =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
        })

      # Create a credential outside the threshold
      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 30, :minute)
      })

      # Mock should only be called for the expiring credential
      expect(SalesforceTokenRefresherMock, :refresh_credential, fn credential ->
        assert credential.id == expiring_cred.id
        {:ok, credential}
      end)

      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end

    test "handles refresh errors gracefully" do
      user = user_fixture()

      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
      })

      expect(SalesforceTokenRefresherMock, :refresh_credential, fn _credential ->
        {:error, :refresh_failed}
      end)

      # Worker should still return :ok even when refresh fails
      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end

    test "refreshes multiple expiring credentials" do
      user = user_fixture()

      cred1 =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3, :minute)
        })

      cred2 =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 5, :minute)
        })

      expected_ids = MapSet.new([cred1.id, cred2.id])

      expect(SalesforceTokenRefresherMock, :refresh_credential, 2, fn credential ->
        assert MapSet.member?(expected_ids, credential.id)
        {:ok, credential}
      end)

      assert :ok = perform_job(SalesforceTokenRefresher, %{})
    end
  end
end
