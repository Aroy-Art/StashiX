/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import {exitReader} from "../reader_exit.js"

// EpubReader: the text reader's EPUB view, laid out by foliate-js.
//
// The book is never downloaded whole: foliate-js asks a loader for entries
// as it needs them (the package, then each chapter, its styles and
// pictures), and the loader fetches them one at a time from
// /api/books/:id/epub/<entry>. The entry list with sizes comes first, so
// foliate-js can size the book for progress without reading it.
//
// Book content is untrusted HTML shown in blob: iframes that run as this
// page; the page's CSP (StashixWeb.Plugs.ReaderCSP) is what stops its
// scripts. Nothing here relaxes that.
//
// Takes the same commands as the PDF hook ("text:goto", "text:step",
// "text:view", "text:search") and reports with the same events. Progress is
// foliate-js locations (~1500 bytes each): "page_changed" carries the
// location, the total, the contents entry it is under and the exact spot
// (CFI, section href, share of the book), which the server saves.

const FOLIATE = "/vendor/foliate/"
let foliatePromise = null

// Variables, not literals, so esbuild leaves the imports alone: foliate-js
// is served as is from /vendor and only fetched when an EPUB is opened.
// view.js registers <foliate-view>.
const loadFoliate = () => {
  const [view, epub, notes] = ["view.js", "epub.js", "footnotes.js"].map((f) => FOLIATE + f)
  foliatePromise ||= Promise.all([import(view), import(epub), import(notes)]).then(([, {EPUB}, {FootnoteHandler}]) => ({
    EPUB,
    FootnoteHandler,
  }))
  return foliatePromise
}

const THEMES = {
  paper: {bg: "#fbfaf6", fg: "#1d1c1a", link: "#5534c2", scheme: "light"},
  sepia: {bg: "#f1e7d0", fg: "#41321f", link: "#7a4510", scheme: "light"},
  night: {bg: "#141416", fg: "#d6d2c9", link: "#7fd6e0", scheme: "dark"},
}
const FONTS = {
  serif: '"Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif',
  sans: 'system-ui, "Segoe UI", Roboto, "Helvetica Neue", sans-serif',
}
const LINE_HEIGHTS = {tight: 1.3, normal: 1.55, loose: 1.85}
const GAPS = {narrow: "3%", normal: "6%", wide: "11%"}

const REPORT_MS = 150
const ZONE_SIDE = 0.25   // paged: side taps turn the page
const MAX_RESULTS = 500

// The book's CSS loses to these where reading comfort is at stake: colours,
// size, spacing and (unless "original") the font.
const bookCSS = ({theme, font, spacing, size}) => {
  const t = THEMES[theme] || THEMES.paper
  const family = FONTS[font]
  return `
    @namespace epub "http://www.idpf.org/2007/ops";
    html {
      color-scheme: ${t.scheme};
      background: ${t.bg} !important;
      color: ${t.fg} !important;
      font-size: ${size}% !important;
    }
    body { background: none !important; color: inherit !important; }
    p, li, blockquote, dd, dt { line-height: ${LINE_HEIGHTS[spacing] || 1.55} !important; }
    a:any-link { color: ${t.link} !important; }
    pre { white-space: pre-wrap !important; }
    ${family ? `body, body :not(pre, code, kbd, samp, tt, pre *, code *) { font-family: ${family} !important; }` : ""}
    ${t.scheme === "dark" ? `body * { color: inherit !important; background-color: transparent !important; }
      img, svg { filter: brightness(0.85); }` : ""}
    aside[epub|type~="footnote"], aside[epub|type~="endnote"], aside[epub|type~="rearnote"] { display: none; }
  `
}

const EpubReader = {
  mounted() {
    const d = this.el.dataset
    this.url = d.url
    this.start = Number(d.start) || 0
    this.startCfi = d.cfi || null
    this.total = Number(d.total) || 0
    this.settings = {
      layout: d.layout,
      theme: d.pageTheme,
      font: d.font,
      spacing: d.spacing,
      margins: d.margins,
      size: Number(d.size) || 100,
    }
    this.searchToken = 0
    this.atEnd = false
    this.loaded = false

    this.handleEvent("reader:exit", ({to}) => exitReader(this, to))
    this.handleEvent("text:goto", ({page, target}) => this.goto({page, target}))
    this.handleEvent("text:step", ({by}) => (by > 0 ? this.next() : this.view?.prev()))
    this.handleEvent("text:view", (settings) => this.apply({...this.settings, ...settings}))
    this.handleEvent("text:search", ({query}) => this.search(query))

    this.onKey = (e) => this.key(e)
    window.addEventListener("keydown", this.onKey)

    this.open().catch((err) => {
      console.error("EpubReader:", err)
      this.pushEvent("failed", {})
    })
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKey)
    clearTimeout(this.reportTimer)
    this.searchToken++
    this.view?.close()
  },

  async open() {
    const {EPUB, FootnoteHandler} = await loadFoliate()
    const {entries} = await fetch(this.url, {credentials: "same-origin"}).then((r) => {
      if (!r.ok) throw new Error(`entries: ${r.status}`)
      return r.json()
    })

    // Entry names are paths inside the zip; each segment is encoded on its own.
    const entryURL = (name) => `${this.url}/${name.split("/").map(encodeURIComponent).join("/")}`
    const fetchEntry = async (name) => {
      const r = await fetch(entryURL(name), {credentials: "same-origin"})
      if (!r.ok) throw new Error(`${name}: ${r.status}`)
      return r
    }
    // Same contract as foliate-js's own zip loader: null for a missing entry.
    const loader = {
      loadText: (name) => (name in entries ? fetchEntry(name).then((r) => r.text()) : null),
      loadBlob: (name, type) =>
        name in entries ? fetchEntry(name).then((r) => r.blob()).then((b) => (type ? new Blob([b], {type}) : b)) : null,
      getSize: (name) => entries[name] ?? 0,
    }

    this.book = await new EPUB(loader).init()
    this.view = document.createElement("foliate-view")
    this.view.className = "epub-view"
    this.el.append(this.view)
    this.note = this.buildNote()

    await this.view.open(this.book)
    this.view.addEventListener("relocate", (e) => this.relocated(e.detail))
    this.view.addEventListener("load", (e) => this.docLoaded(e.detail))

    // Footnote links open in a small view of their own instead of jumping.
    this.notes = new FootnoteHandler()
    this.notes.addEventListener("before-render", (e) => this.styleNote(e.detail.view))
    this.notes.addEventListener("render", () => this.showNote())
    this.view.addEventListener("link", (e) => this.notes.handle(this.book, e)?.catch((err) => console.error(err)))

    this.apply(this.settings)
    this.outline()

    // Resume at the spot the server has; books saved before it kept one, at
    // the same share of the book.
    if (this.startCfi) await this.view.init({lastLocation: this.startCfi})
    else if (this.start > 0 && this.total > 0) await this.view.goToFraction(this.start / this.total)
    else await this.view.init({showTextStart: false})
  },

  // ── settings ──────────────────────────────────────────────────────────

  apply(settings) {
    this.settings = settings
    if (!this.view?.renderer) return
    const r = this.view.renderer
    const paged = settings.layout !== "scroll"
    // Each attribute change lays the book out again: only set what changed.
    const attrs = {
      flow: paged ? "paginated" : "scrolled",
      gap: GAPS[settings.margins] || GAPS.normal,
      // Room for the bars above and below the text.
      margin: "56px",
      "max-inline-size": "720px",
      "max-column-count": paged ? "2" : "1",
    }
    for (const [name, value] of Object.entries(attrs)) {
      if (r.getAttribute(name) !== value) r.setAttribute(name, value)
    }
    const css = bookCSS(settings)
    if (css !== this.css) {
      this.css = css
      r.setStyles?.(css)
    }
    this.el.dataset.pageTheme = settings.theme
    this.el.style.background = (THEMES[settings.theme] || THEMES.paper).bg
  },

  // ── position ──────────────────────────────────────────────────────────

  relocated(detail) {
    const {fraction, location, tocItem, cfi, section} = detail
    if (!location) return
    this.location = location
    this.section = section
    if (!this.loaded) {
      this.loaded = true
      this.pushEvent("loaded", {page_count: Math.max(location.total, 1)})
    }
    clearTimeout(this.reportTimer)
    this.reportTimer = setTimeout(() => {
      this.pushEvent("page_changed", {
        page: location.current,
        total: location.total,
        toc: tocItem?.href ?? null,
        cfi,
        href: this.view.book.sections?.[section?.current]?.id ?? null,
        fraction,
      })
    }, REPORT_MS)

    // Scrolled flow: reaching the end of the last section shows the end card.
    if (this.settings.layout === "scroll") {
      const end = fraction >= 0.995
      if (end !== this.atEnd) this.pushEvent("scroll_end", {visible: end})
      this.atEnd = end
    }
  },

  lastSection() {
    return this.section && this.section.current >= this.section.total - 1
  },

  // Paged: past the last page the server shows the end card.
  next() {
    if (!this.view) return
    if (this.settings.layout !== "scroll" && this.lastSection() && this.view.renderer.atEnd) {
      this.pushEvent("paged_end", {})
      return
    }
    this.view.next()
  },

  goto({page, target}) {
    if (!this.view) return
    if (target) this.view.goTo(target)
    else if (page != null && this.location?.total) this.view.goToFraction(Math.min(page / this.location.total, 0.9999))
  },

  // ── input ─────────────────────────────────────────────────────────────

  // Each chapter is its own document: keys and taps there never reach this
  // page, so they are wired up per document as it loads.
  docLoaded({doc}) {
    doc.addEventListener("keydown", this.onKey)
    let down = null
    doc.addEventListener("pointerdown", (e) => { down = {x: e.clientX, y: e.clientY} })
    doc.addEventListener("click", (e) => {
      if (e.defaultPrevented || e.target.closest?.("a[href]")) return
      if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 8) return
      if (!doc.defaultView.getSelection()?.isCollapsed) return
      this.tap(e.clientX + (doc.defaultView.frameElement?.getBoundingClientRect().left ?? 0))
    })
  },

  tap(x) {
    if (this.closeNote()) return
    const rect = this.el.getBoundingClientRect()
    const at = (x - rect.left) / rect.width
    if (this.settings.layout !== "scroll") {
      if (at < ZONE_SIDE) return this.view.goLeft()
      if (at > 1 - ZONE_SIDE) return this.book.dir === "rtl" ? this.view.goLeft() : this.next()
    }
    this.pushEvent("toggle_overlay", {})
  },

  key(e) {
    if (e.target.closest?.("input, textarea, select, [contenteditable]")) return
    if (e.ctrlKey || e.metaKey || e.altKey || !this.view) return
    const rtl = this.book?.dir === "rtl"

    if (e.key === "Escape") return this.closeNote() || this.pushEvent("close_panel", {})
    if (e.key === "+" || e.key === "=") this.pushEvent("zoom", {by: 1})
    else if (e.key === "-") this.pushEvent("zoom", {by: -1})
    else if (e.key === "0") this.pushEvent("zoom", {by: 0})
    else if (e.key === "ArrowRight") rtl ? this.view.prev() : this.next()
    else if (e.key === "ArrowLeft") rtl ? this.next() : this.view.prev()
    else if (e.key === "Home") this.view.goToFraction(0)
    else if (e.key === "End") this.view.goToFraction(0.9999)
    else if (this.settings.layout === "scroll") return
    else if (["ArrowDown", "PageDown", " "].includes(e.key)) e.shiftKey ? this.view.prev() : this.next()
    else if (["ArrowUp", "PageUp"].includes(e.key)) this.view.prev()
    else return
    e.preventDefault()
  },

  // ── footnotes ─────────────────────────────────────────────────────────

  buildNote() {
    const note = document.createElement("div")
    note.className = "epub-note"
    note.hidden = true
    this.el.append(note)
    return note
  },

  // The note's view loads before "render" fires, so it must already be in
  // the page (an iframe out of the DOM has no document); it waits there
  // unseen until then.
  styleNote(view) {
    this.closeNote()
    view.className = "epub-note-view"
    this.note.replaceChildren(view)
    this.note.style.background = (THEMES[this.settings.theme] || THEMES.paper).bg
    this.note.style.visibility = "hidden"
    this.note.hidden = false
    view.renderer.setAttribute("flow", "scrolled")
    view.renderer.setAttribute("margin", "0px")
    view.renderer.setAttribute("gap", "5%")
    view.renderer.setStyles?.(bookCSS({...this.settings, size: Math.round(this.settings.size * 0.9)}))
  },

  showNote() {
    this.note.style.visibility = "visible"
  },

  closeNote() {
    if (!this.note || this.note.hidden) return false
    this.note.hidden = true
    this.note.firstChild?.close?.()
    this.note.replaceChildren()
    return true
  },

  // ── contents ──────────────────────────────────────────────────────────

  outline() {
    const items = []
    const walk = (nodes, depth) => {
      for (const node of nodes || []) {
        if (items.length >= 2000) return
        items.push({title: (node.label || "").trim() || "—", target: node.href || null, depth})
        walk(node.subitems, depth + 1)
      }
    }
    walk(this.book.toc, 0)
    this.pushEvent("outline", {items})
  },

  // ── search ────────────────────────────────────────────────────────────

  async search(query) {
    const token = ++this.searchToken
    this.view?.clearSearch()
    if (!query || !this.view) return

    let found = 0
    let batch = []
    const send = (done) => {
      this.pushEvent("search_results", {query, results: batch, done})
      batch = []
    }
    for await (const result of this.view.search({query})) {
      if (token !== this.searchToken) return
      if (result === "done") break
      for (const {cfi, excerpt} of result.subitems || []) {
        batch.push({target: cfi, label: result.label || null, before: excerpt.pre, match: excerpt.match, after: excerpt.post})
        if (++found >= MAX_RESULTS) break
      }
      if (found >= MAX_RESULTS) break
      if (batch.length >= 20) send(false)
    }
    if (token === this.searchToken) send(true)
  },
}

export default EpubReader
