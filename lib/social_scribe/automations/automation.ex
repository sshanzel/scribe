defmodule SocialScribe.Automations.Automation do
  @moduledoc """
  Schema for user-defined content generation automations.

  An automation defines a template for generating social media content
  from meeting transcripts. Users can create automations for different
  platforms with custom descriptions and examples.

  ## Fields

  - `name` - Human-readable name for the automation
  - `description` - Instructions for content generation
  - `platform` - Target platform (:linkedin or :facebook)
  - `example` - Example output to guide the AI
  - `is_active` - Whether the automation is currently enabled

  ## Associations

  - `user` - The user who owns this automation
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "automations" do
    field :name, :string
    field :description, :string
    field :platform, Ecto.Enum, values: [:linkedin, :facebook]
    field :example, :string
    field :is_active, :boolean, default: true

    belongs_to :user, SocialScribe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(automation, attrs) do
    automation
    |> cast(attrs, [:name, :platform, :description, :example, :is_active, :user_id])
    |> validate_required([:name, :platform, :description, :example, :is_active, :user_id])
  end
end
