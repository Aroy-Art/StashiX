# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Format do
  @moduledoc """
  Numbers for display in the current Gettext locale: digit grouping, the
  decimal separator, and the short K/M forms. Sizes and weights come from
  `Stashix.Formatters` and only get their decimal separator swapped here.

  Dates are formatted in the browser instead, see `StashixWeb.CoreComponents.local_time/1`.
  """
  use Gettext, backend: StashixWeb.Gettext

  alias Stashix.Formatters
  alias StashixWeb.Locale

  @doc "An integer with digit grouping: 12345 → \"12,345\" (en), \"12.345\" (de)."
  def integer(n) when is_integer(n) do
    {group, _decimal} = Locale.number_symbols()
    sign = if n < 0, do: "-", else: ""

    digits =
      n
      |> abs()
      |> Integer.to_string()
      |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, group)

    sign <> digits
  end

  @doc """
  A number with `decimals` places (trailing zeros kept), or a `Decimal` as is,
  with the locale's separators.
  """
  def decimal(n, decimals \\ 1)
  def decimal(%Decimal{} = n, _decimals), do: n |> Decimal.to_string(:normal) |> localize()
  def decimal(n, _decimals) when is_integer(n), do: integer(n)
  def decimal(n, decimals) when is_float(n), do: n |> :erlang.float_to_binary(decimals: decimals) |> localize()

  @doc "A count in a short form for big figures: 950, 12.3K, 4.5M."
  def compact(n) when n >= 1_000_000, do: gettext("%{number}M", number: decimal(n / 1_000_000))
  def compact(n) when n >= 1_000, do: gettext("%{number}K", number: decimal(n / 1_000))
  def compact(n), do: integer(n)

  @doc "A byte count, see `Stashix.Formatters.format_bytes/2`."
  def bytes(bytes, base \\ :binary), do: bytes |> Formatters.format_bytes(base) |> localize()

  @doc "A file size, or nil when unknown, see `Stashix.Formatters.format_file_size/1`."
  def file_size(bytes), do: bytes |> Formatters.format_file_size() |> localize()

  @doc "The weight of printing that many pages, see `Stashix.Formatters.format_paper_weight/1`."
  def paper_weight(pages), do: pages |> Formatters.format_paper_weight() |> localize()

  # Swaps the decimal point of an English-formatted number for the locale's,
  # and groups its integer part.
  defp localize(nil), do: nil

  defp localize(text) do
    {group, decimal} = Locale.number_symbols()

    Regex.replace(~r/(\d+)(?:\.(\d+))?/, text, fn _number, whole, fraction ->
      whole = String.replace(whole, ~r/\B(?=(\d{3})+(?!\d))/, group)
      if fraction == "", do: whole, else: whole <> decimal <> fraction
    end)
  end
end
