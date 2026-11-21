# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

# render_async and assert_receive wait this long. The 100ms default is too
# tight on a busy machine; it only costs time when a test is failing anyway.
ExUnit.start(assert_receive_timeout: 2_000)
Ecto.Adapters.SQL.Sandbox.mode(Stashix.Repo, :manual)
