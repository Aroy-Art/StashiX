/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// Path of the page the reader was opened from, i.e. the history entry right
// below it. Leaving the reader for that same page pops back onto it instead of
// stacking a second copy; anything else replaces the reader's entry. Either way
// the reader is gone from the history, so "back" never reopens it. Shared by
// the comic reader and the text reader.
let pageBelowReader = null
const pathOf = (href) => new URL(href, window.location.href).pathname
const isReaderPath = (path) => path.startsWith("/read/")
if (!isReaderPath(window.location.pathname)) pageBelowReader = window.location.pathname
window.addEventListener("phx:navigate", ({detail}) => {
  const path = pathOf(detail.href)
  if (!isReaderPath(path)) pageBelowReader = path
  // Reached by back/forward: what sits below is no longer the page we last saw.
  else if (detail.pop) pageBelowReader = null
})

// Answers the server's "reader:exit" event for `hook`.
export const exitReader = (hook, to) => {
  if (pageBelowReader === to) window.history.back()
  else hook.js().navigate(to, {replace: true})
}
