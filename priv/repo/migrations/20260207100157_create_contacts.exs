defmodule SocialScribe.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts) do
      add :name, :string
      add :email, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contacts, [:email])
  end
end
