# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use StashixWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint StashixWeb.Endpoint

      use StashixWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import StashixWeb.ConnCase
    end
  end

  @doc """
  `Phoenix.LiveViewTest.live/2` that follows the redirect a detail page gives
  a UUID (or stale slug) param on its way to the canonical slug URL.
  """
  defmacro live_canonical(conn, path) do
    quote do
      conn = unquote(conn)

      case Phoenix.LiveViewTest.live(conn, unquote(path)) do
        {:error, {:live_redirect, %{to: to}}} -> Phoenix.LiveViewTest.live(conn, to)
        other -> other
      end
    end
  end

  setup tags do
    Stashix.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
