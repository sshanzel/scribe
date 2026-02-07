defmodule SocialScribe.Repo.Migrations.RemoveUserIdFromContacts do
  use Ecto.Migration

  def change do
    # Drop existing indexes
    drop index(:contacts, [:user_id])
    drop index(:contacts, [:email])
    drop unique_index(:contacts, [:user_id, :email])

    # Remove user_id column and make email not null
    alter table(:contacts) do
      remove :user_id
      modify :email, :string, null: false
    end

    # Add new unique index on email only (global contacts)
    create unique_index(:contacts, [:email])
  end
end
