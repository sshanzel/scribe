defmodule SocialScribe.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages) do
      add :thread_id, references(:chat_threads, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text, null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:chat_messages, [:thread_id])
  end
end
