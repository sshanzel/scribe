defmodule SocialScribe.ChatFixtures do
  @moduledoc """
  Fixtures for creating chat threads and messages in tests.
  """

  alias SocialScribe.Chat

  def chat_thread_fixture(attrs \\ %{}) do
    user =
      attrs[:user] ||
        attrs[:user_id] ||
        SocialScribe.AccountsFixtures.user_fixture()

    user_struct = if is_map(user), do: user, else: %SocialScribe.Accounts.User{id: user}

    {:ok, thread} =
      Chat.create_thread(user_struct, %{
        title: attrs[:title]
      })

    thread
  end

  def chat_message_fixture(attrs \\ %{}) do
    thread =
      attrs[:thread] ||
        attrs[:thread_id] ||
        chat_thread_fixture()

    thread_struct = if is_map(thread), do: thread, else: %SocialScribe.Chat.ChatThread{id: thread}

    {:ok, message} =
      Chat.create_message(thread_struct, %{
        role: attrs[:role] || "user",
        content: attrs[:content] || "Hello, this is a test message",
        metadata: attrs[:metadata] || %{}
      })

    message
  end
end
