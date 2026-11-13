# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.FormatTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import StashixWeb.CoreComponents, only: [local_time: 1]

  alias StashixWeb.Format

  setup do
    Gettext.put_locale(StashixWeb.Gettext, "en")
    :ok
  end

  describe "in English" do
    test "groups digits" do
      assert Format.integer(0) == "0"
      assert Format.integer(999) == "999"
      assert Format.integer(1_234_567) == "1,234,567"
      assert Format.integer(-12_345) == "-12,345"
    end

    test "decimals and short forms" do
      assert Format.decimal(4.0) == "4.0"
      assert Format.decimal(Decimal.new("1234.50")) == "1,234.50"
      assert Format.compact(950) == "950"
      assert Format.compact(12_345) == "12.3K"
      assert Format.compact(4_500_000) == "4.5M"
    end

    test "sizes" do
      assert Format.bytes(1_288_490_189) == "1.2 GiB"
      assert Format.bytes(150 * 1_073_741_824) == "150 GiB"
      assert Format.file_size(nil) == nil
    end
  end

  describe "in German" do
    setup do
      Gettext.put_locale(StashixWeb.Gettext, "de")
      :ok
    end

    test "swaps the separators" do
      assert Format.integer(1_234_567) == "1.234.567"
      assert Format.decimal(Decimal.new("1234.50")) == "1.234,50"
      assert Format.bytes(1_288_490_189) == "1,2 GiB"
      assert Format.bytes(150 * 1_073_741_824) == "150 GiB"
      assert Format.paper_weight(1_000_000) == "2,50 t"
    end
  end

  test "a locale without its own symbols falls back to its language, then English" do
    Gettext.put_locale(StashixWeb.Gettext, "pt_BR")
    assert Format.integer(1234) == "1.234"
    Gettext.put_locale(StashixWeb.Gettext, "pt_PT")
    assert Format.integer(1234) == "1 234"
    Gettext.put_locale(StashixWeb.Gettext, "ja")
    assert Format.integer(1234) == "1,234"
  end

  describe "local_time/1" do
    test "renders a date as is, for the hook to format" do
      assigns = %{}

      assert rendered_to_string(~H|<.local_time id="d" value={~D[2026-11-12]} />|) ==
               ~s(<time id="d" datetime="2026-11-12" data-format="date" phx-hook="LocalTime">2026-11-12</time>)
    end

    test "treats naive date-times as UTC" do
      assigns = %{}

      html = rendered_to_string(~H|<.local_time id="t" value={~N[2026-11-12 14:03:59.123]} format="datetime" />|)
      assert html =~ ~s(datetime="2026-11-12T14:03:59Z")
      assert html =~ ">2026-11-12 14:03</time>"
    end

    test "months fall back to year and month" do
      assigns = %{}
      html = rendered_to_string(~H|<.local_time id="m" value={~U[2026-11-12 14:03:00Z]} format="month" />|)
      assert html =~ ">2026-11</time>"
    end
  end
end
