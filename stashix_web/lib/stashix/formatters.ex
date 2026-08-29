defmodule Stashix.Formatters do
  @base2_units [{"TiB", 1_099_511_627_776}, {"GiB", 1_073_741_824}, {"MiB", 1_048_576}, {"KiB", 1_024}]
  @base10_units [{"TB", 1_000_000_000_000}, {"GB", 1_000_000_000}, {"MB", 1_000_000}, {"KB", 1_000}]

  def format_bytes(bytes, base \\ :binary)

  def format_bytes(%Decimal{} = bytes, base), do: format_bytes(Decimal.to_integer(bytes), base)

  def format_bytes(bytes, base) do
    units = if base == :decimal, do: @base10_units, else: @base2_units
    {suffix, divisor} = Enum.find(units, List.last(units), fn {_, d} -> bytes >= d end)
    value = bytes / divisor
    formatted = if value < 10, do: Float.round(value, 2), else: if(value < 100, do: Float.round(value, 1), else: trunc(value))
    "#{formatted} #{suffix}"
  end
end
