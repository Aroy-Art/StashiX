defmodule Stashix.Metadata.Sources.HelpersTest do
  use ExUnit.Case, async: true

  import Stashix.Metadata.Sources.Helpers

  describe "strip_html/1" do
    test "drops cover tables and their heading" do
      html = """
      <p>Belle returns!</p><h4>List of covers and their creators:</h4>
      <table data-max-width="true"><thead><tr><th>Cover</th><th>Name</th><th>Creator(s)</th><th>Sidebar Location</th></tr></thead>
      <tbody><tr><td>A</td><td>Regular Cover</td><td>Winston Young</td><td>1</td></tr>
      <tr><td>B</td><td>Risqué Cover, Limited to 2500</td><td>Winston Young</td><td>2</td></tr></tbody></table>
      """

      assert strip_html(html) == "Belle returns!"
    end

    test "keeps headings not followed by a table" do
      assert strip_html("<h4>Synopsis</h4><p>Text</p>") == "SynopsisText"
    end

    test "returns nil when only a table remains" do
      assert strip_html("<h4>List of covers</h4><table><tr><td>A</td></tr></table>") == nil
    end
  end

  describe "strip_cover_list/1" do
    @junk "List of covers and their creators:CoverNameCreator(s)Sidebar LocationARegular CoverWinston Young1"

    test "cuts a flattened cover table off the end" do
      assert strip_cover_list("Belle returns!\n\n" <> @junk) == "Belle returns!"
      assert strip_cover_list("Belle returns!" <> @junk) == "Belle returns!"
    end

    test "returns nil when nothing else is left" do
      assert strip_cover_list(@junk) == nil
    end

    test "leaves other summaries alone" do
      assert strip_cover_list("List of covers and their creators: see below") ==
               "List of covers and their creators: see below"

      assert strip_cover_list(nil) == nil
    end
  end
end
