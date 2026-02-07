defmodule SocialScribe.Contacts.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Accounts.User

  schema "contacts" do
    field :name, :string
    field :email, :string

    belongs_to :user, User

    timestamps()
  end

  @doc """
  Creates a changeset for inserting or updating a contact.
  """
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:user_id, :name, :email])
    |> validate_required([:user_id, :email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint([:user_id, :email],
      name: :contacts_user_id_email_index,
      message: "contact already exists for this user"
    )
  end

  @doc """
  Returns the display name for the contact.
  Falls back to email if name is not set.
  """
  def display_name(%__MODULE__{name: name, email: email}) do
    if name && name != "", do: name, else: email
  end
end
