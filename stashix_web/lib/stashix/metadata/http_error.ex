# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Metadata.HTTP.Error do
  defexception [:reason]

  @impl true
  def message(%{reason: reason}), do: Stashix.Metadata.HTTP.error_message(reason)
end
