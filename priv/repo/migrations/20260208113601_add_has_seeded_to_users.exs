defmodule SocialScribe.Repo.Migrations.AddHasSeededToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :has_seeded, :boolean, default: false, null: false
    end
  end
end
