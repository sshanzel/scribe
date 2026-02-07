defmodule SocialScribe.ChatTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Chat
  alias SocialScribe.Chat.{ChatThread, ChatMessage}
  import SocialScribe.AccountsFixtures

  # =============================================================================
  # Thread Tests
  # =============================================================================

  describe "create_thread/2" do
    test "creates a thread for a user" do
      user = user_fixture()

      assert {:ok, %ChatThread{} = thread} = Chat.create_thread(user)
      assert thread.user_id == user.id
      assert thread.title == nil
    end

    test "creates a thread with title" do
      user = user_fixture()

      assert {:ok, %ChatThread{} = thread} =
               Chat.create_thread(user, %{title: "Q1 Budget Discussion"})

      assert thread.title == "Q1 Budget Discussion"
    end
  end

  describe "update_thread/2" do
    test "updates thread title" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      assert {:ok, updated} = Chat.update_thread(thread, %{title: "New Title"})
      assert updated.title == "New Title"
    end
  end

  describe "delete_thread/1" do
    test "deletes a thread" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      assert {:ok, _} = Chat.delete_thread(thread)
      assert_raise Ecto.NoResultsError, fn -> Chat.get_thread!(thread.id) end
    end

    test "cascade deletes messages" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)
      {:ok, message} = Chat.create_user_message(thread, "Hello")

      Chat.delete_thread(thread)

      assert_raise Ecto.NoResultsError, fn -> Chat.get_message!(message.id) end
    end
  end

  describe "get_thread!/1" do
    test "returns the thread with messages" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)
      {:ok, _} = Chat.create_user_message(thread, "Hello")

      fetched = Chat.get_thread!(thread.id)

      assert fetched.id == thread.id
      assert length(fetched.messages) == 1
    end

    test "raises on not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_thread!(999_999)
      end
    end
  end

  describe "get_thread_for_user/2" do
    test "returns thread when user owns it" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      assert {:ok, fetched} = Chat.get_thread_for_user(user, thread.id)
      assert fetched.id == thread.id
    end

    test "returns error when thread not found" do
      user = user_fixture()

      assert {:error, :not_found} = Chat.get_thread_for_user(user, 999_999)
    end

    test "returns error when user does not own thread" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, thread} = Chat.create_thread(user1)

      assert {:error, :unauthorized} = Chat.get_thread_for_user(user2, thread.id)
    end
  end

  describe "list_threads/1" do
    test "returns threads ordered by most recent" do
      user = user_fixture()
      {:ok, thread1} = Chat.create_thread(user, %{title: "Thread 1"})

      # Wait to ensure different second for timestamp
      Process.sleep(1000)

      {:ok, thread2} = Chat.create_thread(user, %{title: "Thread 2"})

      threads = Chat.list_threads(user)

      assert length(threads) == 2
      # thread2 was created later so it should be first
      assert hd(threads).id == thread2.id

      # Now touch thread1 to make it most recent
      Process.sleep(1000)
      Chat.touch_thread(thread1)

      threads = Chat.list_threads(user)
      assert hd(threads).id == thread1.id
    end

    test "returns empty list for user with no threads" do
      user = user_fixture()

      assert Chat.list_threads(user) == []
    end

    test "does not return other users' threads" do
      user1 = user_fixture()
      user2 = user_fixture()
      {:ok, _} = Chat.create_thread(user1)

      assert Chat.list_threads(user2) == []
    end
  end

  describe "list_threads_with_messages/1" do
    test "returns threads with messages preloaded" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)
      {:ok, _} = Chat.create_user_message(thread, "Hello")

      [fetched] = Chat.list_threads_with_messages(user)

      assert fetched.id == thread.id
      assert length(fetched.messages) == 1
    end
  end

  # =============================================================================
  # Message Tests
  # =============================================================================

  describe "create_message/2" do
    test "creates a message in a thread" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      attrs = %{role: "user", content: "Hello, what did John say?"}

      assert {:ok, %ChatMessage{} = message} = Chat.create_message(thread, attrs)
      assert message.thread_id == thread.id
      assert message.role == "user"
      assert message.content == "Hello, what did John say?"
    end

    test "creates a message with metadata" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      attrs = %{
        role: "user",
        content: "What did @John say?",
        metadata: %{"mentions" => [%{"contact_id" => 123, "name" => "John"}]}
      }

      assert {:ok, message} = Chat.create_message(thread, attrs)
      assert message.metadata["mentions"] == [%{"contact_id" => 123, "name" => "John"}]
    end

    test "updates thread's updated_at" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)
      original_updated_at = thread.updated_at

      # Wait to ensure different second for timestamp (timestamps are truncated to seconds)
      Process.sleep(1000)

      {:ok, _} = Chat.create_user_message(thread, "Hello")

      updated_thread = Chat.get_thread!(thread.id)
      assert NaiveDateTime.compare(updated_thread.updated_at, original_updated_at) == :gt
    end
  end

  describe "create_user_message/3" do
    test "creates a user message" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      assert {:ok, message} = Chat.create_user_message(thread, "Hello")
      assert message.role == "user"
      assert message.content == "Hello"
    end

    test "creates a user message with metadata" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      metadata = %{"mentions" => [%{"contact_id" => 1}]}

      assert {:ok, message} = Chat.create_user_message(thread, "Hello @John", metadata)
      assert message.metadata == metadata
    end
  end

  describe "create_assistant_message/3" do
    test "creates an assistant message" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      assert {:ok, message} = Chat.create_assistant_message(thread, "Hello, how can I help?")
      assert message.role == "assistant"
      assert message.content == "Hello, how can I help?"
    end

    test "creates an assistant message with metadata" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      metadata = %{"meeting_refs" => [%{"meeting_id" => 456}], "tokens_used" => 1000}

      assert {:ok, message} = Chat.create_assistant_message(thread, "Response", metadata)
      assert message.metadata == metadata
    end
  end

  describe "list_messages/1" do
    test "returns messages in chronological order" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      {:ok, msg1} = Chat.create_user_message(thread, "First")
      {:ok, msg2} = Chat.create_assistant_message(thread, "Second")
      {:ok, msg3} = Chat.create_user_message(thread, "Third")

      messages = Chat.list_messages(thread)

      assert length(messages) == 3
      assert Enum.map(messages, & &1.id) == [msg1.id, msg2.id, msg3.id]
    end

    test "returns empty list for thread with no messages" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      assert Chat.list_messages(thread) == []
    end
  end

  describe "get_message!/1" do
    test "returns the message" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)
      {:ok, message} = Chat.create_user_message(thread, "Hello")

      assert Chat.get_message!(message.id).id == message.id
    end

    test "raises on not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Chat.get_message!(999_999)
      end
    end
  end

  describe "count_messages/1" do
    test "counts messages in thread" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      {:ok, _} = Chat.create_user_message(thread, "1")
      {:ok, _} = Chat.create_assistant_message(thread, "2")
      {:ok, _} = Chat.create_user_message(thread, "3")

      assert Chat.count_messages(thread) == 3
    end

    test "returns 0 for empty thread" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      assert Chat.count_messages(thread) == 0
    end
  end

  describe "get_first_user_message/1" do
    test "returns the first user message" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      {:ok, first} = Chat.create_user_message(thread, "First question")
      {:ok, _} = Chat.create_assistant_message(thread, "Answer")
      {:ok, _} = Chat.create_user_message(thread, "Second question")

      result = Chat.get_first_user_message(thread)

      assert result.id == first.id
      assert result.content == "First question"
    end

    test "returns nil for thread with no user messages" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      {:ok, _} = Chat.create_assistant_message(thread, "Only assistant")

      assert Chat.get_first_user_message(thread) == nil
    end

    test "returns nil for empty thread" do
      user = user_fixture()
      {:ok, thread} = Chat.create_thread(user)

      assert Chat.get_first_user_message(thread) == nil
    end
  end
end
