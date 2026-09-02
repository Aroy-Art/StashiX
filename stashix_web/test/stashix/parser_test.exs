defmodule Stashix.Metadata.ParserTest do
  use ExUnit.Case, async: true

  alias Stashix.Metadata.Parser

  defp d(n), do: Decimal.new(n)

  describe "parse_filename/1 — Issue/Volume prefix pattern" do
    test "Issue N - Title" do
      r = Parser.parse_filename("Issue 3 - Angel of Death")
      assert r[:issue_number] == d("3")
      assert r[:title] == "Angel of Death"
    end

    test "Issue N - Title (YEAR)" do
      r = Parser.parse_filename("Issue 6 - Angel of Death (1996)")
      assert r[:issue_number] == d("6")
      assert r[:title] == "Angel of Death"
      assert r[:year] == 1996
    end

    test "Volume N - Title" do
      r = Parser.parse_filename("Volume 3 - Killing Angel")
      assert r[:issue_number] == d("3")
      assert r[:title] == "Killing Angel"
    end

    test "Vol. N - Title" do
      r = Parser.parse_filename("Vol. 2 - Dark Chapter")
      assert r[:issue_number] == d("2")
      assert r[:title] == "Dark Chapter"
    end
  end

  describe "parse_filename/1 — Series Vol. NN (YEAR) pattern" do
    test "standalone volume — title strips Vol. suffix" do
      r = Parser.parse_filename("Pariah Vol. 01 (2014) (digital) (Minutemen-Slayer)")
      assert r[:title] == "Pariah"
      assert r[:volume] == 1
      assert r[:year] == 2014
    end

    test "does not steal Series - Vol. N (YEAR) dash pattern" do
      r = Parser.parse_filename("Some Mag – Vol. 7 (2022)")
      assert r[:issue_number] == d("7")
      assert r[:year] == 2022
    end

    test "Volume keyword (no dot) with year" do
      r = Parser.parse_filename("9-11 Volume 1 (2002) (c2c) (SuperFriends-DCP)")
      assert r[:series] == "9-11"
      assert r[:volume] == 1
      assert r[:year] == 2002
    end

    test "Volume keyword without year" do
      r = Parser.parse_filename("9-11 Volume 2 (ActionComics-DCP)")
      assert r[:series] == "9-11"
      assert r[:volume] == 2
    end
  end

  describe "parse_filename/1 — Series N (YEAR) pattern" do
    test "Series N (YEAR)" do
      r = Parser.parse_filename("Batman 001 (1940)")
      assert r[:series] == "Batman"
      assert r[:issue_number] == d("1")
      assert r[:year] == 1940
    end

    test "multi-word series" do
      r = Parser.parse_filename("Amazing Spider-Man 045 (1967)")
      assert r[:series] == "Amazing Spider-Man"
      assert r[:issue_number] == d("45")
      assert r[:year] == 1967
    end
  end

  describe "parse_filename/1 — Series NN (Publisher-YEAR) pattern" do
    test "publisher embedded with year in parens" do
      r = Parser.parse_filename("Jonny Demon 02 (Dark Horse-1994) (Novus Year Three) (Rumor-Novus-HD)")
      assert r[:series] == "Jonny Demon"
      assert r[:issue_number] == d("2")
      assert r[:year] == 1994
    end
  end

  describe "parse_filename/1 — Series (YEAR) - Chapter N pattern" do
    test "Chapter keyword" do
      r = Parser.parse_filename("Berserk (1989) - Chapter 12")
      assert r[:series] == "Berserk"
      assert r[:year] == 1989
      assert r[:issue_number] == d("12")
    end

    test "Ch. abbreviation" do
      r = Parser.parse_filename("One Piece (1997) - Ch. 5")
      assert r[:series] == "One Piece"
      assert r[:year] == 1997
      assert r[:issue_number] == d("5")
    end
  end

  describe "parse_filename/1 — Series (YEAR) - Issue N pattern" do
    test "exact user-reported filename" do
      r = Parser.parse_filename("Bubblegum Crisis: Grand Mal (1994) - Issue 3")
      assert r[:series] == "Bubblegum Crisis: Grand Mal"
      assert r[:year] == 1994
      assert r[:issue_number] == d("3")
    end

    test "issue 1 (first issue)" do
      r = Parser.parse_filename("Saga (2012) - Issue 1")
      assert r[:series] == "Saga"
      assert r[:year] == 2012
      assert r[:issue_number] == d("1")
    end

    test "Iss. abbreviation" do
      r = Parser.parse_filename("Monstress (2015) - Iss. 7")
      assert r[:series] == "Monstress"
      assert r[:year] == 2015
      assert r[:issue_number] == d("7")
    end

    test "decimal issue number" do
      r = Parser.parse_filename("X-Men (1991) - Issue 2.5")
      assert r[:series] == "X-Men"
      assert r[:year] == 1991
      assert r[:issue_number] == d("2.5")
    end

    test "year range in folder" do
      r = Parser.parse_filename("Bubblegum Crisis: Grand Mal (1994-1995) - Issue 2")
      assert r[:series] == "Bubblegum Crisis: Grand Mal"
      assert r[:year] == 1994
      assert r[:issue_number] == d("2")
    end

  end

  describe "parse_filename/1 — Series NN - Title (Publisher YEAR) pattern" do
    test "user-reported filename" do
      r = Parser.parse_filename("The Bank 01 - The Waterloo Insider (Cinebook 2025) (webrip) (MagicMan-DCP)")
      assert r[:series] == "The Bank"
      assert r[:issue_number] == d("1")
      assert r[:title] == "The Waterloo Insider"
      assert r[:year] == 2025
      assert r[:source_format] == "webrip"
    end

    test "decimal issue number" do
      r = Parser.parse_filename("Thorgal 13.5 - Between Life and Death (Le Lombard 1988)")
      assert r[:series] == "Thorgal"
      assert r[:issue_number] == d("13.5")
      assert r[:title] == "Between Life and Death"
      assert r[:year] == 1988
    end

    test "no publisher, just year in parens" do
      r = Parser.parse_filename("Spawn 001 - Darkness Within (1992)")
      assert r[:series] == "Spawn"
      assert r[:issue_number] == d("1")
      assert r[:title] == "Darkness Within"
      assert r[:year] == 1992
    end

    test "digital tag captured as source_format" do
      r = Parser.parse_filename("Batman 100 - Joker War (DC 2020) (Digital)")
      assert r[:source_format] == "digital"
      assert r[:issue_number] == d("100")
    end

    test "c2c tag captured as source_format" do
      r = Parser.parse_filename("Superman 1 - Man of Steel (DC 1986) (c2c)")
      assert r[:source_format] == "c2c"
    end

    test "no source_format when no tag" do
      r = Parser.parse_filename("Saga 001 - Chapter One (Image 2012)")
      assert r[:source_format] == nil
    end
  end

  describe "parse_filename/1 — Series (YEAR) general pattern" do
    test "series with year only — no issue" do
      r = Parser.parse_filename("Watchmen (1986)")
      assert r[:series] == "Watchmen"
      assert r[:year] == 1986
      assert r[:issue_number] == nil
    end

    test "series with year and hash issue number" do
      r = Parser.parse_filename("Daredevil (1964) #012")
      assert r[:series] == "Daredevil"
      assert r[:year] == 1964
      assert r[:issue_number] == d("12")
    end

    test "series with year and volume and issue" do
      r = Parser.parse_filename("Judge Dredd (1977) v2 #5")
      assert r[:series] == "Judge Dredd"
      assert r[:year] == 1977
      assert r[:volume] == 2
      assert r[:issue_number] == d("5")
    end
  end

  describe "parse_filename/1 — volume-based pattern" do
    test "Series v1 with issue" do
      r = Parser.parse_filename("Akira v1 #38")
      assert r[:series] == "Akira"
      assert r[:volume] == 1
      assert r[:issue_number] == d("38")
    end
  end

  describe "parse_filename/1 — trailing number pattern" do
    test "Series trailing number" do
      r = Parser.parse_filename("Hellboy 003")
      assert r[:series] == "Hellboy"
      assert r[:issue_number] == d("3")
    end
  end

  describe "parse_filename/1 — noise stripping" do
    test "strips Digital tag" do
      r = Parser.parse_filename("Saga (2012) - Issue 1 (Digital)")
      assert r[:issue_number] == d("1")
    end

    test "strips c2c tag" do
      r = Parser.parse_filename("Batman 001 (1940) (c2c)")
      assert r[:issue_number] == d("1")
    end

    test "strips (of N) issue count tag" do
      r = Parser.parse_filename("Aliens - Dust to Dust 01 (of 04) (2018) (digital) (The Magicians-Empire)")
      assert r[:issue_number] == d("1")
      assert r[:year] == 2018
    end
  end

  describe "parse_filename/1 — en-dash in filename" do
    test "en-dash separator produces clean title (no stray UTF-8 bytes)" do
      r = Parser.parse_filename("Metal Hurlant 02 – Space Stares Back (2025) (digital) (juvecube)")
      assert r[:series] == "Metal Hurlant"
      assert r[:issue_number] == d("2")
      assert r[:title] == "Space Stares Back"
      assert r[:year] == 2025
      assert String.valid?(r[:title])
    end

    test "en-dash in Vol. NNN pattern" do
      r = Parser.parse_filename("Some Mag – Vol. 7 (2022)")
      assert r[:issue_number] == d("7")
      assert r[:year] == 2022
    end
  end

  describe "parse_filename/1 — no match falls back to title" do
    test "plain title with no pattern" do
      r = Parser.parse_filename("My Random File")
      assert r[:title] == "My Random File"
      assert r[:issue_number] == nil
    end
  end

  describe "parse_filename/1 — Series - cNN Title (YEAR) pattern" do
    test "c-prefix chapter with title and year" do
      r = Parser.parse_filename("Amulet - c01 The Stonekeeper (2008)")
      assert r[:series] == "Amulet"
      assert r[:issue_number] == d("1")
      assert r[:title] == "The Stonekeeper"
      assert r[:year] == 2008
    end

    test "hash-prefix chapter with title and year" do
      r = Parser.parse_filename("Bone - #03 Eyes of the Storm (1993)")
      assert r[:series] == "Bone"
      assert r[:issue_number] == d("3")
      assert r[:title] == "Eyes of the Storm"
      assert r[:year] == 1993
    end

    test "en-dash separator variant" do
      r = Parser.parse_filename("Amulet – c02 The Stonekeeper's Curse (2009)")
      assert r[:series] == "Amulet"
      assert r[:issue_number] == d("2")
      assert r[:year] == 2009
    end
  end

  describe "parse_filename/1 — ongoing series (YEAR-) pattern" do
    test "c-prefix chapter in ongoing series" do
      r = Parser.parse_filename("Amulet (2008-) c01 The Stonekeeper")
      assert r[:series] == "Amulet"
      assert r[:year] == 2008
      assert r[:issue_number] == d("1")
    end

    test "zero-padded issue in ongoing series" do
      r = Parser.parse_filename("Invincible (2003-) 001 (Digital)")
      assert r[:series] == "Invincible"
      assert r[:year] == 2003
      assert r[:issue_number] == d("1")
    end

    test "chapter keyword in ongoing series" do
      r = Parser.parse_filename("One-Punch Man (2012-) - Chapter 100")
      assert r[:series] == "One-Punch Man"
      assert r[:year] == 2012
      assert r[:issue_number] == d("100")
    end

    test "issue keyword in ongoing series" do
      r = Parser.parse_filename("Saga (2012-) - Issue 3")
      assert r[:series] == "Saga"
      assert r[:year] == 2012
      assert r[:issue_number] == d("3")
    end

    test "existing year-range (YEAR-YEAR) still works" do
      r = Parser.parse_filename("Batman (2011-2016) 001 (Digital)")
      assert r[:series] == "Batman"
      assert r[:year] == 2011
      assert r[:issue_number] == d("1")
    end
  end

  describe "parse_filename/1 — Vol. NNN after dash pattern" do
    test "Vol. NNN followed by year" do
      r = Parser.parse_filename("Heavy Metal Magazine #202011 - Vol. 302 (2020) (2 covers) (Digital) (Mephisto-Empire)")
      assert r[:issue_number] == d("302")
      assert r[:year] == 2020
    end

    test "Vol. NNN with subtitle before year" do
      r = Parser.parse_filename("Heavy Metal Magazine #201806 - Vol. 290: Deadly Special (2018) (4 covers) (Digital) (Mephisto-Empire)")
      assert r[:issue_number] == d("290")
      assert r[:year] == 2018
    end

    test "simple Vol. NNN" do
      r = Parser.parse_filename("Some Magazine - Vol. 15 (2023)")
      assert r[:issue_number] == d("15")
      assert r[:year] == 2023
    end

    test "Vol. NNN with subtitle and no extra tags" do
      r = Parser.parse_filename("Some Magazine - Vol. 15: Special Edition (2023)")
      assert r[:issue_number] == d("15")
      assert r[:year] == 2023
    end
  end

  describe "parse_filename/1 — Series #NN (MM-YYYY) pattern" do
    test "hash issue with month-year date" do
      r = Parser.parse_filename("Clockwork Angels #06 (of 06) (11-2014)")
      assert r[:series] == "Clockwork Angels"
      assert r[:issue_number] == d("6")
      assert r[:year] == 2014
    end

    test "hash issue with bare year" do
      r = Parser.parse_filename("Some Series #12 (2019)")
      assert r[:series] == "Some Series"
      assert r[:issue_number] == d("12")
      assert r[:year] == 2019
    end

    test "hash issue with noise tags" do
      r = Parser.parse_filename("Saga #001 (Digital) (01-2022)")
      assert r[:series] == "Saga"
      assert r[:issue_number] == d("1")
      assert r[:year] == 2022
    end
  end
end
