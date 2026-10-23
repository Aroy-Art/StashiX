# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.ImporterTest do
  use ExUnit.Case, async: true

  alias Stashix.Metadata.Importer

  describe "web_url?/1" do
    test "accepts http(s) links with a host" do
      assert Importer.web_url?("https://comicvine.gamespot.com/x/4000-1/")
      assert Importer.web_url?(" http://metron.cloud/issue/1/ ")
    end

    test "rejects other schemes and junk" do
      refute Importer.web_url?("javascript:alert(1)")
      refute Importer.web_url?("JaVaScRiPt:alert(1)")
      refute Importer.web_url?("data:text/html,x")
      refute Importer.web_url?("https://")
      refute Importer.web_url?("not a url")
      refute Importer.web_url?("")
      refute Importer.web_url?(nil)
    end
  end
end
