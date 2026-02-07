defmodule SocialScribe.Chat.ChatMessage do
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
