# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Locale do
  @moduledoc """
  Picks the interface language for each request: the account's setting, or
  with "auto" (and for signed-out pages) the browser's Accept-Language, or the
  default locale.

  As a plug in the browser pipeline it sets the Gettext locale for the dead
  render and stores it in the session. LiveViews run in their own process, so
  the `on_mount` hook (added to every LiveView in `StashixWeb.live_view/0`)
  sets it again from that session.

  The choice is only read on a full page load: after changing it, redirect
  instead of patching so the root layout is rendered again.
  """
  @behaviour Plug

  import Plug.Conn

  alias Stashix.Accounts.User
  alias Stashix.Auth.TokenHelper

  @backend StashixWeb.Gettext
  @default_locale Application.compile_env(:stashix, [@backend, :default_locale], "en")

  # Endonyms for the language picker; unknown codes show as the code.
  @names %{
    "ar" => "العربية",
    "cs" => "Čeština",
    "da" => "Dansk",
    "de" => "Deutsch",
    "en" => "English",
    "es" => "Español",
    "fi" => "Suomi",
    "fr" => "Français",
    "it" => "Italiano",
    "ja" => "日本語",
    "ko" => "한국어",
    "nb" => "Norsk bokmål",
    "nl" => "Nederlands",
    "pl" => "Polski",
    "pt" => "Português",
    "pt_BR" => "Português (Brasil)",
    "ru" => "Русский",
    "sv" => "Svenska",
    "tr" => "Türkçe",
    "uk" => "Українська",
    "zh_CN" => "简体中文",
    "zh_TW" => "繁體中文"
  }

  @doc "The locale's name in its own language, for the picker."
  def name(locale), do: Map.get(@names, locale, locale)

  @doc "The current Gettext locale as an HTML `lang` value (`pt_BR` → `pt-BR`)."
  def html_lang, do: @backend |> Gettext.get_locale() |> String.replace("_", "-")

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    locale = resolve(account_locale(conn), get_req_header(conn, "accept-language"))
    Gettext.put_locale(@backend, locale)
    put_session(conn, "locale", locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = session["locale"]
    if locale in User.locales(), do: Gettext.put_locale(@backend, locale)
    {:cont, socket}
  end

  defp account_locale(conn) do
    case TokenHelper.user_from_session(get_session(conn)) do
      {:ok, user} -> User.locale(user)
      {:error, _} -> "auto"
    end
  end

  @doc """
  The account's choice unless it is "auto", then the best match for the
  Accept-Language header values, then the default locale.
  """
  def resolve(choice, accept_language, known \\ User.locales()) do
    cond do
      choice in known -> choice
      match = best_match(accept_language, known) -> match
      true -> @default_locale
    end
  end

  @doc """
  The first locale in `known` the header asks for, by quality: an exact
  match (`pt-BR` → `pt_BR`), or failing that the same language (`de-AT` →
  `de`, `pt` → `pt_BR`).
  """
  def best_match(headers, known) do
    headers
    |> List.wrap()
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&parse_range/1)
    |> Enum.reject(fn {tag, q} -> tag == "" or q <= 0 end)
    |> Enum.sort_by(fn {_tag, q} -> q end, :desc)
    |> Enum.find_value(fn {tag, _q} -> match(tag, known) end)
  end

  defp parse_range(range) do
    [tag | params] = range |> String.trim() |> String.split(";")

    q =
      Enum.find_value(params, 1.0, fn param ->
        with ["q", value] <- param |> String.trim() |> String.split("=", parts: 2),
             {q, _} <- Float.parse(value) do
          q
        else
          _ -> nil
        end
      end)

    {normalize(tag), q}
  end

  # "pt-br" → "pt_BR", the form Gettext names its directories in.
  defp normalize(tag) do
    case tag |> String.trim() |> String.split(["-", "_"]) do
      [lang, region | _] -> String.downcase(lang) <> "_" <> String.upcase(region)
      [lang] -> String.downcase(lang)
    end
  end

  defp match(tag, known) do
    lang = tag |> String.split("_") |> hd()

    cond do
      tag in known -> tag
      lang in known -> lang
      true -> Enum.find(known, &String.starts_with?(&1, lang <> "_"))
    end
  end
end
