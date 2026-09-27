defmodule Stashix.Library.BookCredit do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # MetronInfo uses "Cover" for this role; stored as "Cover Artist" to avoid
  # ambiguity with the cover image itself. Map "Cover" → "Cover Artist" on import.
  @roles [
    :Writer,
    :Script,
    :Story,
    :Plot,
    :Interviewer,
    :Artist,
    :Penciller,
    :Breakdowns,
    :Illustrator,
    :Layouts,
    :Inker,
    :Embellisher,
    :Finishes,
    :"Ink Assists",
    :Colorist,
    :"Color Separations",
    :"Color Assists",
    :"Color Flats",
    :"Digital Art Technician",
    :"Gray Tone",
    :Letterer,
    :"Cover Artist",
    :Editor,
    :"Consulting Editor",
    :"Assistant Editor",
    :"Associate Editor",
    :"Group Editor",
    :"Senior Editor",
    :"Managing Editor",
    :"Collection Editor",
    :Production,
    :Designer,
    :"Logo Design",
    :Translator,
    :"Supervising Editor",
    :"Executive Editor",
    :"Editor in Chief",
    :President,
    :Publisher,
    :"Chief Creative Officer",
    :"Executive Producer",
    :"General Manager",
    :"Production Manager",
    :"Brand Manager",
    :"VP of Business Affairs",
    :"VP of Marketing",
    :"VP of Publicity",
    :"VP of Sales",
    :Other
  ]

  schema "book_credits" do
    field :role, Ecto.Enum, values: @roles

    belongs_to :book, Stashix.Library.Book
    belongs_to :creator, Stashix.Library.Creator

    timestamps()
  end

  def changeset(credit, attrs) do
    credit
    |> cast(attrs, [:book_id, :creator_id, :role])
    |> validate_required([:book_id, :creator_id, :role])
    |> unique_constraint([:book_id, :creator_id, :role])
  end
end
