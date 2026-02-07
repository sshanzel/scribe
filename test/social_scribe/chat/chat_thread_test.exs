defmodule SocialScribe.Chat.ChatThreadTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Chat.ChatThread
  import SocialScribe.AccountsFixtures

  describe "changeset/2" do
    test "valid changeset with user_id only" do
      user = user_fixture()

      attrs = %{
        user_id: user.id
      }

      changeset = ChatThread.changeset(%ChatThread{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with title" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        title: "Discussion about Q1 budget"
      }

      changeset = ChatThread.changeset(%ChatThread{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without user_id" do
      attrs = %{
        title: "Some thread"
      }

      changeset = ChatThread.changeset(%ChatThread{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "persists thread to database" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        title: "Test Thread"
      }

      {:ok, thread} =
        %ChatThread{}
        |> ChatThread.changeset(attrs)
        |> Repo.insert()

      assert thread.id
      assert thread.user_id == user.id
      assert thread.title == "Test Thread"
    end

    test "thread is deleted when user is deleted" do
      user = user_fixture()

      {:ok, thread} =
        %ChatThread{}
        |> ChatThread.changeset(%{user_id: user.id, title: "Test"})
        |> Repo.insert()

      Repo.delete!(user)

      assert Repo.get(ChatThread, thread.id) == nil
    end
  end
end
