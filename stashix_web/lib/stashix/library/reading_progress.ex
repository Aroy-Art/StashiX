defmodule Stashix.Library.ReadingProgress do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "reading_progress" do
    field :current_page, :integer, default: 0
    field :updated_at, :naive_datetime

    belongs_to :user, Stashix.Accounts.User
    belongs_to :book, Stashix.Library.Book
  end

  def changeset(progress, attrs) do
    progress
    |> cast(attrs, [:current_page, :user_id, :book_id, :updated_at])
    |> validate_required([:current_page, :user_id, :book_id])
    |> unique_constraint([:user_id, :book_id])
  end
end
