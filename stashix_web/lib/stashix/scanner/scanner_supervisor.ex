# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule Stashix.Scanner.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Task.Supervisor, name: Stashix.Scanner.TaskSupervisor},
      Stashix.Scanner,
      Stashix.Scanner.FileWatcher
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
