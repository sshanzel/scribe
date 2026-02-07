defmodule SocialScribe.Chat do
  @moduledoc """
  The Chat context for managing chat threads and messages.

  Threads are private to each user and contain messages between
  the user and the AI assistant.
  """

  import Ecto.Query, warn: false

  alias SocialScribe.Repo
  alias SocialScribe.Chat.{ChatThread, ChatMessage}
  alias SocialScribe.Accounts.User

  # =============================================================================
  # Thread Management
  # =============================================================================

  @doc """
  Creates a new chat thread for a user.
  """
  def create_thread(%User{} = user, attrs \\ %{}) do
    %ChatThread{}
    |> ChatThread.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Updates an existing chat thread.
  """
  def update_thread(%ChatThread{} = thread, attrs) do
    thread
    |> ChatThread.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a chat thread and all its messages.
  """
  def delete_thread(%ChatThread{} = thread) do
    Repo.delete(thread)
  end

  @doc """
  Gets a thread by ID.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_thread!(id) do
    ChatThread
    |> Repo.get!(id)
    |> Repo.preload(:messages)
  end

  @doc """
  Gets a thread by ID for a specific user.

  Returns {:ok, thread} if found and owned by user,
  {:error, :not_found} if not found,
  {:error, :unauthorized} if owned by another user.
  """
  def get_thread_for_user(%User{id: user_id}, thread_id) do
    case Repo.get(ChatThread, thread_id) do
      nil ->
        {:error, :not_found}

      %ChatThread{user_id: ^user_id} = thread ->
        {:ok, Repo.preload(thread, :messages)}

      %ChatThread{} ->
        {:error, :unauthorized}
    end
  end

  @doc """
  Lists all threads for a user, ordered by most recent first.
  """
  def list_threads(%User{id: user_id}), do: list_threads(user_id)

  def list_threads(user_id) when is_integer(user_id) do
    ChatThread
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.updated_at)
    |> Repo.all()
  end

  @doc """
  Lists threads for a user with their messages preloaded.
  """
  def list_threads_with_messages(%User{id: user_id}) do
    ChatThread
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.updated_at)
    |> preload(:messages)
    |> Repo.all()
  end

  @doc """
  Touches a thread to update its updated_at timestamp.
  """
  def touch_thread(%ChatThread{} = thread) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    thread
    |> Ecto.Changeset.change(%{updated_at: now})
    |> Repo.update()
  end

  # =============================================================================
  # Message Management
  # =============================================================================

  @doc """
  Creates a new message in a thread.
  """
  def create_message(%ChatThread{} = thread, attrs) do
    result =
      %ChatMessage{}
      |> ChatMessage.changeset(Map.put(attrs, :thread_id, thread.id))
      |> Repo.insert()

    # Update thread's updated_at timestamp
    case result do
      {:ok, message} ->
        touch_thread(thread)
        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Creates a user message in a thread.
  """
  def create_user_message(%ChatThread{} = thread, content, metadata \\ %{}) do
    create_message(thread, %{
      role: "user",
      content: content,
      metadata: metadata
    })
  end

  @doc """
  Creates an assistant message in a thread.
  """
  def create_assistant_message(%ChatThread{} = thread, content, metadata \\ %{}) do
    create_message(thread, %{
      role: "assistant",
      content: content,
      metadata: metadata
    })
  end

  @doc """
  Lists all messages in a thread, ordered by creation time.
  """
  def list_messages(%ChatThread{id: thread_id}), do: list_messages(thread_id)

  def list_messages(thread_id) when is_integer(thread_id) do
    ChatMessage
    |> where([m], m.thread_id == ^thread_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a message by ID.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_message!(id), do: Repo.get!(ChatMessage, id)

  @doc """
  Counts messages in a thread.
  """
  def count_messages(%ChatThread{id: thread_id}) do
    ChatMessage
    |> where([m], m.thread_id == ^thread_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Returns the first user message in a thread (for title generation).
  """
  def get_first_user_message(%ChatThread{id: thread_id}) do
    ChatMessage
    |> where([m], m.thread_id == ^thread_id and m.role == "user")
    |> order_by([m], asc: m.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
