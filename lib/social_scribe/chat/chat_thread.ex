defmodule SocialScribe.Chat.ChatThread do
  @moduledoc """
  Schema for chat conversation threads.

  A thread represents a conversation between a user and the AI assistant.
  Threads can have an optional title that is generated after the first
  message exchange.

  ## Fields

  - `title` - Optional title summarizing the conversation topic
  - `user_id` - The user who owns this thread

  ## Associations

  - `user` - The user who owns this thread
  - `messages` - All messages in this thread
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User
  alias SocialScribe.Chat.ChatMessage

  @type t :: %__MODULE__{}

  schema "chat_threads" do
    field :title, :string

    belongs_to :user, User
    has_many :messages, ChatMessage, foreign_key: :thread_id

    timestamps()
  end

  @doc """
  Creates a changeset for inserting or updating a chat thread.
  """
  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:user_id, :title])
    |> validate_required([:user_id])
  end
end
