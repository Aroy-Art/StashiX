defmodule StashixWeb.ErrorHTMLTest do
  use StashixWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html" do
    html = render_to_string(StashixWeb.ErrorHTML, "404", "html", [])
    assert html =~ "This page isn&#39;t there"
    assert html =~ ~s(href="/")
  end

  test "renders 500.html" do
    html = render_to_string(StashixWeb.ErrorHTML, "500", "html", [])
    assert html =~ "A page tore"
  end

  test "falls back to the status message for codes without their own copy" do
    assert render_to_string(StashixWeb.ErrorHTML, "418", "html", []) =~ "I&#39;m a teapot"
  end
end
