defmodule SocialScribe.Chat.ChatMessageTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Chat.{ChatThread, ChatMessage}
  import SocialScribe.AccountsFixtures

  def thread_fixture(attrs \\ %{}) do
    user = attrs[:user] || user_fixture()

    {:ok, thread} =
      %ChatThread{}
      |> ChatThread.changeset(%{user_id: user.id, title: "Test Thread"})
      |> Repo.insert()

    thread
  end

  describe "changeset/2" do
    test "valid changeset with required fields" do
      thread = thread_fixture()

      attrs = %{
        thread_id: thread.id,
        role: "user",
        content: "What did John say about the budget?"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with metadata" do
      thread = thread_fixture()

      attrs = %{
        thread_id: thread.id,
        role: "user",
        content: "What did @John Doe say about the budget?",
        metadata: %{
          "mentions" => [%{"contact_id" => 123, "name" => "John Doe", "start" => 9, "end" => 18}]
        }
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "valid changeset with assistant role" do
      thread = thread_fixture()

      attrs = %{
        thread_id: thread.id,
        role: "assistant",
        content: "In the Q1 Planning meeting, John mentioned..."
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      assert changeset.valid?
    end

    test "invalid changeset without thread_id" do
      attrs = %{
        role: "user",
        content: "Hello"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).thread_id
    end

    test "invalid changeset without role" do
      thread = thread_fixture()

      attrs = %{
        thread_id: thread.id,
        content: "Hello"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).role
    end

    test "invalid changeset without content" do
      thread = thread_fixture()

      attrs = %{
        thread_id: thread.id,
        role: "user"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).content
    end

    test "invalid changeset with invalid role" do
      thread = thread_fixture()

      attrs = %{
        thread_id: thread.id,
        role: "invalid",
        content: "Hello"
      }

      changeset = ChatMessage.changeset(%ChatMessage{}, attrs)
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "messages are deleted when thread is deleted" do
      thread = thread_fixture()

      {:ok, message} =
        %ChatMessage{}
        |> ChatMessage.changeset(%{
          thread_id: thread.id,
          role: "user",
          content: "Test message"
        })
        |> Repo.insert()

      Repo.delete!(thread)

      assert Repo.get(ChatMessage, message.id) == nil
    end
  end

  describe "mentions/1" do
    test "returns mentions from metadata" do
      mentions = [%{"contact_id" => 123, "name" => "John Doe", "start" => 9, "end" => 18}]

      message = %ChatMessage{
        metadata: %{"mentions" => mentions}
      }

      assert ChatMessage.mentions(message) == mentions
    end

    test "returns empty list when no mentions" do
      message = %ChatMessage{metadata: %{}}
      assert ChatMessage.mentions(message) == []
    end

    test "returns empty list when metadata is nil" do
      message = %ChatMessage{metadata: nil}
      assert ChatMessage.mentions(message) == []
    end
  end

  describe "meeting_refs/1" do
    test "returns meeting refs from metadata" do
      refs = [%{"meeting_id" => 456, "title" => "Q1 Planning", "date" => "2025-01-15"}]

      message = %ChatMessage{
        metadata: %{"meeting_refs" => refs}
      }

      assert ChatMessage.meeting_refs(message) == refs
    end

    test "returns empty list when no meeting refs" do
      message = %ChatMessage{metadata: %{}}
      assert ChatMessage.meeting_refs(message) == []
    end

    test "returns empty list when metadata is nil" do
      message = %ChatMessage{metadata: nil}
      assert ChatMessage.meeting_refs(message) == []
    end
  end
end
