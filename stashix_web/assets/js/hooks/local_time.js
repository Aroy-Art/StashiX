/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// LocalTime: formats a <.local_time> in the page language and the viewer's
// time zone. The server's ISO text stays if the browser can't parse it.
const OPTIONS = {
  date: {dateStyle: "medium"},
  datetime: {dateStyle: "medium", timeStyle: "short"},
  month: {year: "numeric", month: "long"},
  month_short: {year: "numeric", month: "short"},
}

const format = (el) => {
  const value = el.getAttribute("datetime")
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return

  const options = {...(OPTIONS[el.dataset.format] || OPTIONS.date)}
  // A plain date ("2026-11-12") parses as UTC midnight; formatting it in a
  // zone west of UTC would show the day before.
  if (!value.includes("T")) options.timeZone = "UTC"

  try {
    el.textContent = new Intl.DateTimeFormat(document.documentElement.lang || undefined, options).format(date)
  } catch (_) {}
}

const LocalTime = {
  mounted() {
    format(this.el)
  },
  // A patch puts the server's text back.
  updated() {
    format(this.el)
  },
}

export default LocalTime
