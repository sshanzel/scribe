defmodule SocialScribe.Bots.UserBotPreference do
  @moduledoc """
  Schema for user preferences related to Recall.ai bot behavior.

  Stores user-specific settings for how bots should behave, such as when
  they should join meetings relative to the scheduled start time.

  ## Fields

  - `join_minute_offset` - Minutes before/after the meeting start when the bot joins (0-10)
  - `user_id` - The user these preferences belong to
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_bot_preferences" do
    field :join_minute_offset, :integer, default: 2
    belongs_to :user, SocialScribe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_bot_preference, attrs) do
    user_bot_preference
    |> cast(attrs, [:user_id, :join_minute_offset])
    |> validate_required([:user_id, :join_minute_offset])
    |> unique_constraint(:user_id)
    |> validate_inclusion(:join_minute_offset, 0..10, message: "must be between 0 and 10")
  end
end
