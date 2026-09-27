defmodule Stashix.Metadata.Candidate do
  @moduledoc """
  A search result from a metadata source. `kind` is `:series` or `:issue`.
  `score` is filled in by `Stashix.Metadata.Matcher`.
  """

  @derive {Jason.Encoder, except: [:raw]}
  defstruct [
    :source_key,
    :kind,
    :id,
    :series_id,
    :series_name,
    :number,
    :title,
    :year,
    :publisher,
    :cover_url,
    :page_count,
    :issue_count,
    :url,
    :raw,
    score: 0.0
  ]

  @type t :: %__MODULE__{}

  @fields ~w(source_key kind id series_id series_name number title year publisher cover_url page_count issue_count url score)a

  @doc "Plain string-keyed map for JSON storage in `metadata_match_reviews.candidates`."
  def to_map(%__MODULE__{} = c) do
    Map.new(@fields, fn f -> {Atom.to_string(f), encode(Map.get(c, f))} end)
  end

  def from_map(%{} = m) do
    attrs =
      Enum.map(@fields, fn f ->
        v = Map.get(m, Atom.to_string(f), Map.get(m, f))
        {f, if(f == :kind and is_binary(v), do: String.to_existing_atom(v), else: v)}
      end)

    struct(__MODULE__, attrs)
  end

  defp encode(v) when is_atom(v) and not is_nil(v) and not is_boolean(v), do: Atom.to_string(v)
  defp encode(v), do: v
end
