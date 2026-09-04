defmodule Stashix.Formatters do
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

  def language_name(nil), do: nil
  def language_name(code), do: Map.get(@language_names, String.downcase(code), code)

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
