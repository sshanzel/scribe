defmodule SocialScribe.Repo.Migrations.CreateChatThreads do
  use Ecto.Migration

  def change do
    create table(:chat_threads) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string

      timestamps(type: :utc_datetime)
    end

    create index(:chat_threads, [:user_id])
  end
end
