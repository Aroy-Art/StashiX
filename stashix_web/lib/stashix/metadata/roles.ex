defmodule Stashix.Metadata.Roles do
  @moduledoc "Groups the detailed MetronInfo credit roles into the few headings shown in the UI."

  @groups [
    {"Writer", ~w(Writer Script Story Plot Interviewer)a},
    {"Artist", ~w(Artist Penciller Illustrator Breakdowns Layouts Inker Embellisher Finishes)a ++ [:"Ink Assists"]},
    {"Colorist",
     [:Colorist, :"Color Separations", :"Color Assists", :"Color Flats", :"Digital Art Technician", :"Gray Tone"]},
    {"Letterer", [:Letterer]},
    {"Cover", [:"Cover Artist"]},
    {"Editor",
     [
       :Editor,
       :"Consulting Editor",
       :"Assistant Editor",
       :"Associate Editor",
       :"Group Editor",
       :"Senior Editor",
       :"Managing Editor",
       :"Collection Editor",
       :"Supervising Editor",
       :"Executive Editor",
       :"Editor in Chief"
     ]},
    {"Translator", [:Translator]}
  ]

  @headline ~w(Writer Artist Cover)

  @lookup for {label, roles} <- @groups, role <- roles, into: %{}, do: {role, label}
  @order @groups |> Enum.map(&elem(&1, 0)) |> Kernel.++(["Other"])

  @doc "Heading for a role atom."
  def group_of(role), do: Map.get(@lookup, role, "Other")

  @doc """
  `[{heading, [{name, id}]}]` in display order from `%BookCredit{creator: %Creator{}}` rows.
  """
  def group(credits) do
    credits
    |> Enum.group_by(&group_of(&1.role), &{&1.creator.name, &1.creator.id})
    |> sort_groups(fn entries -> entries |> Enum.uniq_by(&elem(&1, 0)) end)
  end

  @doc """
  `[{heading, [{name, count, id}]}]` from `{name, role, count, id}` rows (series aggregates).
  """
  def group_counts(rows, limit \\ 8) do
    rows
    |> Enum.group_by(fn {_name, role, _count, _id} -> group_of(role) end, fn {name, _role, count, id} ->
      {name, count, id}
    end)
    |> sort_groups(fn entries ->
      entries
      |> Enum.group_by(fn {name, _count, id} -> {name, id} end, fn {_name, count, _id} -> count end)
      |> Enum.map(fn {{name, id}, counts} -> {name, Enum.max(counts), id} end)
      |> Enum.sort_by(fn {name, count, _id} -> {-count, name} end)
      |> Enum.take(limit)
    end)
  end

  @doc "Only the headline groups (writer, artist, cover) for the compact credits line."
  def headline(groups), do: Enum.filter(groups, fn {label, _} -> label in @headline end)

  defp sort_groups(grouped, fun) do
    grouped
    |> Enum.map(fn {label, items} -> {label, fun.(items)} end)
    |> Enum.sort_by(fn {label, _} -> Enum.find_index(@order, &(&1 == label)) end)
  end
end
