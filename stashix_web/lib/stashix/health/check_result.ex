defmodule Stashix.Health.CheckResult do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @check_types [:integrity, :unsupported_file]
  @statuses [:ok, :error]

  schema "health_check_results" do
    field :check_type, Ecto.Enum, values: @check_types
    field :file_path, :string
    field :status, Ecto.Enum, values: @statuses
    field :error_message, :string
    field :checked_at, :naive_datetime

    belongs_to :library, Stashix.Library.Library
    belongs_to :book_file, Stashix.Library.BookFile

    timestamps()
  end

  def changeset(result, attrs) do
    result
    |> cast(attrs, [:library_id, :book_file_id, :check_type, :file_path, :status, :error_message, :checked_at])
    |> validate_required([:library_id, :check_type, :file_path, :status, :checked_at])
    |> foreign_key_constraint(:library_id)
    |> foreign_key_constraint(:book_file_id)
  end
end
