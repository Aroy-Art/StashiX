# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.RichTextTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import StashixWeb.CoreComponents, only: [rich_text: 1, rich_marker: 1]

  test "fills each placeholder with its part, without extra whitespace" do
    assigns = %{text: "Read the %{license}, at %{source}.", license: "GPL"}

    html =
      rendered_to_string(~H"""
      <.rich_text text={
        String.replace(@text, ["%{license}", "%{source}"], fn
          "%{license}" -> rich_marker("license")
          "%{source}" -> rich_marker("source")
        end)
      }>
        <:part name="license"><a href="/l">{@license}</a></:part>
        <:part name="source"><b>here</b></:part>
      </.rich_text>
      """)

    assert html == ~s(Read the <a href="/l">GPL</a>, at <b>here</b>.)
  end

  test "escapes the translated text" do
    assigns = %{}
    assert rendered_to_string(~H|<.rich_text text="a <b> & c" />|) == "a &lt;b&gt; &amp; c"
  end
end
