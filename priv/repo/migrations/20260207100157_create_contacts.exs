defmodule SocialScribe.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string
      add :email, :string

      timestamps(type: :utc_datetime)
    end

    create index(:contacts, [:user_id])
    create index(:contacts, [:email])
    create unique_index(:contacts, [:user_id, :email])
  end
end
