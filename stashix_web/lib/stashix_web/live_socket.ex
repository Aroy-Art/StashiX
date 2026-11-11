# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.LiveSocket do
  # Stock LiveView socket, but the multi-line "CONNECTED TO" entry Phoenix
  # writes on every page load goes to debug instead of info.
  use Phoenix.LiveView.Socket, log: :debug
end
