defmodule SocialScribe.Automations.AutomationResult do
  @moduledoc """
  Schema for storing results of automation execution.

  When an automation is triggered for a meeting, the generated content
  and status are stored here for review and publishing.

  ## Fields

  - `status` - Current status (e.g., "draft", "published", "generation_failed")
  - `generated_content` - The AI-generated content
  - `error_message` - Error details if generation failed

  ## Associations

  - `automation` - The automation that generated this result
  - `meeting` - The meeting that triggered this result
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "automation_results" do
    field :status, :string
    field :generated_content, :string
    field :error_message, :string

    belongs_to :automation, SocialScribe.Automations.Automation
    belongs_to :meeting, SocialScribe.Meetings.Meeting

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(automation_result, attrs) do
    automation_result
    |> cast(attrs, [:generated_content, :status, :error_message, :automation_id, :meeting_id])
    |> validate_required([
      :status,
      :automation_id,
      :meeting_id
    ])
  end
end
