defmodule SocialScribe.Chat.ChatMessage do
  @moduledoc """
  Schema for individual messages within a chat thread.

  Messages can be from the user or the AI assistant. They store content
  and metadata including contact mentions and meeting references.

  ## Fields

  - `role` - Either "user" or "assistant"
  - `content` - The message text content
  - `metadata` - JSON field containing mentions and meeting references
  - `thread_id` - The chat thread this message belongs to

  ## Metadata Structure

  The metadata field can contain:
  - `mentions` - List of contact mentions with `contact_id`, `name`, `email`
  - `meeting_refs` - List of meeting references used in the response
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Chat.ChatThread

  @roles ~w(user assistant)

  schema "chat_messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}

    belongs_to :thread, ChatThread

    timestamps()
  end

  @doc """
  Creates a changeset for inserting or updating a chat message.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:thread_id, :role, :content, :metadata])
    |> validate_required([:thread_id, :role, :content])
    |> validate_inclusion(:role, @roles)
  end

  @doc """
  Returns the contact mentions from the message metadata.
  """
  def mentions(%__MODULE__{metadata: %{"mentions" => mentions}}) when is_list(mentions) do
    mentions
  end

  def mentions(_), do: []

  @doc """
  Returns the meeting references from the message metadata.
  """
  def meeting_refs(%__MODULE__{metadata: %{"meeting_refs" => refs}}) when is_list(refs) do
    refs
  end

  def meeting_refs(_), do: []
end
