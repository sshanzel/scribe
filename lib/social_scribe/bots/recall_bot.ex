defmodule SocialScribe.Bots.RecallBot do
  @moduledoc """
  Schema for tracking Recall.ai bot instances.

  A RecallBot represents a bot that joins a meeting to record and transcribe it.
  It tracks the bot's status, the Recall.ai bot ID, and links to the user and
  calendar event.

  ## Fields

  - `recall_bot_id` - The unique identifier from Recall.ai
  - `status` - Current bot status (e.g., "pending", "in_meeting", "done")
  - `meeting_url` - The meeting URL the bot joined
  - `user_id` - The user who initiated the recording
  - `calendar_event_id` - The associated calendar event
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "recall_bots" do
    field :status, :string
    field :recall_bot_id, :string
    field :meeting_url, :string

    belongs_to :user, SocialScribe.Accounts.User
    belongs_to :calendar_event, SocialScribe.Calendar.CalendarEvent

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recall_bot, attrs) do
    recall_bot
    |> cast(attrs, [:recall_bot_id, :status, :meeting_url, :user_id, :calendar_event_id])
    |> validate_required([:recall_bot_id, :status, :meeting_url, :user_id, :calendar_event_id])
    |> unique_constraint(:recall_bot_id)
  end
end
