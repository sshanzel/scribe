defmodule SocialScribe.ChatAI do
  @moduledoc """
  AI integration for chat, using Google Gemini for multi-turn conversations.

  This module handles:
  - Resolving contacts from message metadata
  - Generating AI responses via Gemini
  - Generating thread titles

  For context building, see `SocialScribe.ChatAI.ContextBuilder`.
  For prompt building, see `SocialScribe.ChatAI.PromptBuilder`.
  """

  @behaviour SocialScribe.ChatAIApi

  alias SocialScribe.Chat
  alias SocialScribe.Chat.{ChatThread, ChatMessage}
  alias SocialScribe.Contacts
  alias SocialScribe.Contacts.Contact
  alias SocialScribe.Accounts.User
  alias SocialScribe.ChatAI.{ContextBuilder, PromptBuilder}

  require Logger

  @gemini_model "gemini-2.0-flash-lite"
  @gemini_api_base_url "https://generativelanguage.googleapis.com/v1/models"

  # Type definitions
  @type metadata :: %{optional(String.t()) => term()}
  @type error_reason ::
          {:config_error, String.t()}
          | {:api_error, String.t()}
          | {:rate_limited, String.t()}
          | {:service_unavailable, String.t()}
          | {:http_error, String.t()}
          | {:parsing_error, String.t(), term()}
          | :contact_not_found
          | term()

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Generates an AI response for a user message in a chat thread.

  Steps:
  1. Save user message
  2. Resolve contact from metadata
  3. Gather CRM data and meeting context
  4. Build multi-turn Gemini payload
  5. Call Gemini API
  6. Save assistant message
  7. Generate thread title if first message

  Returns {:ok, response_content, response_metadata} or {:error, reason}
  """
  @impl SocialScribe.ChatAIApi
  @spec generate_response(ChatThread.t(), User.t(), String.t(), metadata()) ::
          {:ok, String.t(), map()} | {:error, error_reason()}
  def generate_response(%ChatThread{} = thread, %User{} = user, content, metadata)
      when is_binary(content) and is_map(metadata) do
    with {:ok, user_message} <- Chat.create_user_message(thread, content, metadata),
         {:ok, context} <- gather_context_for_metadata(user, metadata),
         messages <- Chat.list_messages(thread),
         {:ok, response} <- call_gemini_chat(context, messages, content),
         response_metadata <- PromptBuilder.build_response_metadata(context),
         {:ok, _assistant_message} <-
           Chat.create_assistant_message(thread, response, response_metadata) do
      # Generate title if this is the first user message
      maybe_generate_title(thread, user_message)

      {:ok, response, response_metadata}
    end
  end

  # Build context from mention metadata
  # Prioritizes contact_id (direct lookup) then falls back to email
  defp gather_context_for_metadata(user, %{"mentions" => [first_mention | _]} = _metadata)
       when is_map(first_mention) do
    case first_mention do
      %{"contact_id" => contact_id} when is_integer(contact_id) ->
        ContextBuilder.gather_context_from_metadata(user, first_mention)

      %{"crm_data" => _crm_data} ->
        ContextBuilder.gather_context_from_metadata(user, first_mention)

      %{"email" => _email} ->
        ContextBuilder.gather_context_from_metadata(user, first_mention)

      _ ->
        ContextBuilder.gather_context(user, nil)
    end
  end

  defp gather_context_for_metadata(user, _metadata) do
    ContextBuilder.gather_context(user, nil)
  end

  @doc """
  Generates a title for a thread based on its messages.
  """
  @impl SocialScribe.ChatAIApi
  @spec generate_thread_title(ChatThread.t()) :: {:ok, String.t()}
  def generate_thread_title(%ChatThread{} = thread) do
    messages = Chat.list_messages(thread)

    case messages do
      [] ->
        {:ok, "New Chat"}

      [_ | _] = msgs ->
        first_user_msg = Enum.find(msgs, &(&1.role == "user"))
        first_assistant_msg = Enum.find(msgs, &(&1.role == "assistant"))

        if first_user_msg do
          generate_title_from_messages(first_user_msg, first_assistant_msg)
        else
          {:ok, "New Chat"}
        end
    end
  end

  # =============================================================================
  # Contact Resolution
  # =============================================================================

  @doc """
  Resolves a contact from message metadata.
  Returns {:ok, contact} or {:error, :no_contact_tagged}.

  Expects metadata with mentions containing contact_id as integer.
  """
  @spec resolve_contact_from_metadata(map()) ::
          {:ok, Contact.t() | nil} | {:error, :contact_not_found}
  def resolve_contact_from_metadata(%{"mentions" => [%{"contact_id" => id} | _]})
      when is_integer(id) do
    case Contacts.get_contact(id) do
      nil -> {:error, :contact_not_found}
      %Contact{} = contact -> {:ok, contact}
    end
  end

  def resolve_contact_from_metadata(%{mentions: [%{contact_id: id} | _]})
      when is_integer(id) do
    case Contacts.get_contact(id) do
      nil -> {:error, :contact_not_found}
      %Contact{} = contact -> {:ok, contact}
    end
  end

  def resolve_contact_from_metadata(%{"mentions" => []}), do: {:ok, nil}
  def resolve_contact_from_metadata(%{mentions: []}), do: {:ok, nil}
  def resolve_contact_from_metadata(_), do: {:ok, nil}

  # =============================================================================
  # Context Gathering - Delegated to ContextBuilder
  # =============================================================================

  @doc """
  Finds meetings where a contact was an attendee.
  Delegated to ContextBuilder.
  """
  defdelegate find_meetings_for_contact(user, contact), to: ContextBuilder

  @doc """
  Finds the most recent meetings for a user when no specific contact is tagged.
  Delegated to ContextBuilder.
  """
  defdelegate find_recent_meetings_for_user(user), to: ContextBuilder

  # =============================================================================
  # Gemini API Integration
  # =============================================================================

  defp call_gemini_chat(context, thread_messages, current_question) do
    api_key = Application.get_env(:social_scribe, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:error, {:config_error, "Gemini API key is missing"}}
    else
      payload = PromptBuilder.build_gemini_payload(context, thread_messages, current_question)
      path = "/#{@gemini_model}:generateContent?key=#{api_key}"

      case Tesla.post(client(), path, payload) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          extract_gemini_response(body)

        {:ok, %Tesla.Env{status: 429, body: _error_body}} ->
          Logger.warning("Gemini API rate limited")

          {:error,
           {:rate_limited,
            "I'm receiving too many requests right now. Please wait a moment and try again."}}

        {:ok, %Tesla.Env{status: 503, body: _error_body}} ->
          Logger.warning("Gemini API service unavailable")

          {:error,
           {:service_unavailable,
            "The AI service is temporarily unavailable. Please try again in a few moments."}}

        {:ok, %Tesla.Env{status: status, body: error_body}} ->
          Logger.error("Gemini API error: #{status} - #{inspect(error_body)}")

          {:error,
           {:api_error, "Something went wrong while generating a response. Please try again."}}

        {:error, reason} ->
          Logger.error("Gemini HTTP error: #{inspect(reason)}")

          {:error,
           {:http_error,
            "Unable to connect to the AI service. Please check your connection and try again."}}
      end
    end
  end

  defp extract_gemini_response(body) do
    text_path = [
      "candidates",
      Access.at(0),
      "content",
      "parts",
      Access.at(0),
      "text"
    ]

    case get_in(body, text_path) do
      nil -> {:error, {:parsing_error, "No text content found in Gemini response", body}}
      text_content -> {:ok, text_content}
    end
  end

  # =============================================================================
  # Title Generation
  # =============================================================================

  defp maybe_generate_title(%ChatThread{title: nil} = thread, %ChatMessage{id: msg_id}) do
    case Chat.get_first_user_message(thread) do
      %ChatMessage{id: ^msg_id} ->
        # This is the first user message, generate title after response
        Task.start(fn ->
          # Small delay to ensure response is saved
          Process.sleep(500)

          {:ok, title} = generate_thread_title(thread)
          Chat.update_thread(thread, %{title: title})
        end)

      _ ->
        :ok
    end
  end

  defp maybe_generate_title(%ChatThread{}, %ChatMessage{}), do: :ok

  defp generate_title_from_messages(
         %ChatMessage{content: user_content} = _user_message,
         assistant_message
       )
       when is_binary(user_content) do
    api_key = Application.get_env(:social_scribe, :gemini_api_key)

    if is_nil(api_key) or api_key == "" do
      {:ok, truncate_for_title(user_content)}
    else
      assistant_snippet =
        case assistant_message do
          %ChatMessage{content: content} when is_binary(content) ->
            "Assistant's response: #{String.slice(content, 0, 500)}"

          _ ->
            ""
        end

      prompt = """
      Generate a short, concise title (max 6 words) for a chat conversation.
      The title should capture the main topic of the discussion.

      User's question: #{user_content}
      #{assistant_snippet}

      Respond with ONLY the title, no quotes, no explanation.
      """

      payload = %{
        contents: [%{parts: [%{text: prompt}]}]
      }

      path = "/#{@gemini_model}:generateContent?key=#{api_key}"

      case Tesla.post(client(), path, payload) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          case extract_gemini_response(body) do
            {:ok, title} when is_binary(title) -> {:ok, String.trim(title)}
            _ -> {:ok, truncate_for_title(user_content)}
          end

        _ ->
          {:ok, truncate_for_title(user_content)}
      end
    end
  end

  defp truncate_for_title(content) do
    content
    |> String.slice(0, 50)
    |> String.trim()
    |> then(fn s ->
      if String.length(content) > 50, do: s <> "...", else: s
    end)
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @gemini_api_base_url},
      Tesla.Middleware.JSON
    ])
  end
end
