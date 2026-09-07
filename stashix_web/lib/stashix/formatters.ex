defmodule Stashix.Formatters do
  @moduledoc "Display formatting helpers for sizes, ratings, and language codes."

  @base2_units [{"TiB", 1_099_511_627_776}, {"GiB", 1_073_741_824}, {"MiB", 1_048_576}, {"KiB", 1_024}]
  @base10_units [{"TB", 1_000_000_000_000}, {"GB", 1_000_000_000}, {"MB", 1_000_000}, {"KB", 1_000}]

  @language_names %{
    "af" => "Afrikaans", "ar" => "Arabic", "az" => "Azerbaijani", "be" => "Belarusian",
    "bg" => "Bulgarian", "bn" => "Bengali", "bs" => "Bosnian", "ca" => "Catalan",
    "cs" => "Czech", "cy" => "Welsh", "da" => "Danish", "de" => "German",
    "el" => "Greek", "en" => "English", "eo" => "Esperanto", "es" => "Spanish",
    "et" => "Estonian", "eu" => "Basque", "fa" => "Persian", "fi" => "Finnish",
    "fr" => "French", "ga" => "Irish", "gl" => "Galician", "gu" => "Gujarati",
    "he" => "Hebrew", "hi" => "Hindi", "hr" => "Croatian", "hu" => "Hungarian",
    "hy" => "Armenian", "id" => "Indonesian", "is" => "Icelandic", "it" => "Italian",
    "ja" => "Japanese", "ka" => "Georgian", "kk" => "Kazakh", "km" => "Khmer",
    "ko" => "Korean", "lt" => "Lithuanian", "lv" => "Latvian", "mk" => "Macedonian",
    "ml" => "Malayalam", "mn" => "Mongolian", "mr" => "Marathi", "ms" => "Malay",
    "my" => "Burmese", "nb" => "Norwegian", "nl" => "Dutch", "no" => "Norwegian",
    "pa" => "Punjabi", "pl" => "Polish", "pt" => "Portuguese", "ro" => "Romanian",
    "ru" => "Russian", "sk" => "Slovak", "sl" => "Slovenian", "sq" => "Albanian",
    "sr" => "Serbian", "sv" => "Swedish", "sw" => "Swahili", "ta" => "Tamil",
    "te" => "Telugu", "th" => "Thai", "tl" => "Filipino", "tr" => "Turkish",
    "uk" => "Ukrainian", "ur" => "Urdu", "uz" => "Uzbek", "vi" => "Vietnamese",
    "zh" => "Chinese", "zu" => "Zulu"
  }

  @doc "Returns the full language name for a BCP 47 code, or the code itself if unknown. Returns `nil` for `nil`."
  def language_name(nil), do: nil
  def language_name(code), do: Map.get(@language_names, String.downcase(code), code)

  @doc """
  Formats a byte count for display as a file size using SI (decimal) units.

  Returns `nil` for `nil` or `0` so callers can use `|| "—"` for a fallback.
  Delegates to `format_bytes/2` with `:decimal` base.
  """
  def format_file_size(nil), do: nil
  def format_file_size(0), do: nil
  def format_file_size(bytes), do: format_bytes(bytes, :decimal)

  @doc "Formats a content age rating atom as a human-readable string."
  def format_age_rating(:unknown), do: "N/A"
  def format_age_rating(:everyone), do: "Everyone"
  def format_age_rating(:teen), do: "Teen"
  def format_age_rating(:teen_plus), do: "Teen+"
  def format_age_rating(:mature), do: "Mature"
  def format_age_rating(:adult), do: "Adult"
  def format_age_rating(:explicit), do: "Explicit"
  def format_age_rating(_), do: "N/A"

  @doc """
  Formats a byte count with adaptive precision and the given unit base.

  - `:binary` (default) — IEC units: KiB, MiB, GiB, TiB
  - `:decimal` — SI units: KB, MB, GB, TB

  Accepts an integer or `Decimal`. Precision is adaptive: two decimal places
  below 10, one below 100, and integer above that.
  """
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
