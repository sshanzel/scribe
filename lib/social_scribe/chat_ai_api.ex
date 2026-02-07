defmodule SocialScribe.ChatAIApi do
  @moduledoc """
  Behaviour for the chat AI integration.
  Allows for mocking in tests.
  """

  alias SocialScribe.Chat.ChatThread
  alias SocialScribe.Accounts.User

  @callback generate_response(ChatThread.t(), User.t(), String.t(), map()) ::
              {:ok, String.t(), map()} | {:error, any()}

  @callback generate_thread_title(ChatThread.t()) ::
              {:ok, String.t()} | {:error, any()}

  def generate_response(thread, user, content, metadata) do
    impl().generate_response(thread, user, content, metadata)
  end

  def generate_thread_title(thread) do
    impl().generate_thread_title(thread)
  end

  defp impl do
    Application.get_env(
      :social_scribe,
      :chat_ai_api,
      SocialScribe.ChatAI
    )
  end
end
