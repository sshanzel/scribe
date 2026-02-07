defmodule SocialScribe.Chat.ChatThread do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User
  alias SocialScribe.Chat.ChatMessage

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
