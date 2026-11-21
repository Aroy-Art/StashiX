/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import {exitReader} from "../reader_exit.js"
import {AnnotationBar, HIGHLIGHT_COLORS} from "../annotation_bar.js"
import {ReadAloud, ssmlSegments, supported as speechSupported} from "../read_aloud.js"

// EpubReader: the text reader's view for books foliate-js lays out: EPUB,
// Kindle (MOBI, AZW3) and FictionBook.
//
// The book is never downloaded whole where the format allows it:
// - EPUB: foliate-js asks a loader for entries as it needs them (the
//   package, then each chapter, its styles and pictures), and the loader
//   fetches them one at a time from /api/books/:id/epub/<entry>. The entry
//   list with sizes comes first, so foliate-js can size the book for
//   progress without reading it.
// - Kindle: foliate-js reads records out of a File; here a stand-in whose
//   slices are read from /api/books/:id/file in byte ranges of 256 KB,
//   cached.
// - FictionBook: one XML document, fetched whole (the server unzips .fbz);
//   its download is reported ("load_progress") for the server's loading card.
//
// The cover: Kindle and FictionBook books keep it out of the text, and some
// EPUBs leave it out of the reading order. Then it is shown as a page of
// its own in front of the book, outside foliate-js, so the book's sections,
// CFIs and search hits keep their indexes.
//
// Book content is untrusted HTML shown in blob: iframes that run as this
// page; the page's CSP (StashixWeb.Plugs.ReaderCSP) is what stops its
// scripts. Nothing here relaxes that.
//
// Takes the same commands as the PDF hook ("text:goto", "text:step",
// "text:view", "text:search", "annotations:*") and reports with the same
// events. Progress is
// foliate-js locations (~1500 bytes each): "page_changed" carries the
// location, the total, the contents entry it is under and the exact spot
// (CFI, section href, share of the book), which the server saves.

const FOLIATE = "/vendor/foliate/"
let foliatePromise = null

// Variables, not literals, so esbuild leaves the imports alone: foliate-js
// is served as is from /vendor and only fetched when an EPUB is opened.
// view.js registers <foliate-view>.
const loadFoliate = () => {
  const [view, notes, overlayer, cfi] = ["view.js", "footnotes.js", "overlayer.js", "epubcfi.js"].map((f) => FOLIATE + f)
  foliatePromise ||= Promise.all([import(view), import(notes), import(overlayer), import(cfi)]).then(
    ([, {FootnoteHandler}, {Overlayer}, CFI]) => ({FootnoteHandler, Overlayer, CFI}),
  )
  return foliatePromise
}
const foliate = (file) => import(FOLIATE + file)

const fetchOK = async (url, init = {}) => {
  const r = await fetch(url, {credentials: "same-origin", ...init})
  if (!r.ok) throw new Error(`${url}: ${r.status}`)
  return r
}

// The whole response as a Blob, telling onProgress(loaded, total) as it
// arrives; total is 0 when the server doesn't say.
const fetchProgress = async (url, onProgress) => {
  const r = await fetchOK(url)
  const total = Number(r.headers.get("content-length")) || 0
  if (!r.body) return r.blob()
  const reader = r.body.getReader()
  const chunks = []
  let loaded = 0
  for (;;) {
    const {done, value} = await reader.read()
    if (done) break
    chunks.push(value)
    loaded += value.length
    onProgress(loaded, total)
  }
  return new Blob(chunks, {type: r.headers.get("content-type") || ""})
}

// A FictionBook's cover, out of the file itself: foliate-js's getCover
// fetches a data: URL, which the reader's CSP (connect-src) refuses.
const fb2Cover = async (blob) => {
  const doc = new DOMParser().parseFromString(await blob.text(), "application/xml")
  const ref = doc.querySelector("coverpage image")
  const href = ref && [...ref.attributes].find((a) => a.localName === "href")?.value
  if (!href?.startsWith("#")) return null
  const bin = [...doc.getElementsByTagName("binary")].find((b) => b.getAttribute("id") === href.slice(1))
  if (!bin) return null
  const bytes = Uint8Array.from(atob(bin.textContent.replace(/\s/g, "")), (c) => c.charCodeAt(0))
  return new Blob([bytes], {type: bin.getAttribute("content-type") || "image/jpeg"})
}

// A section that is only a picture (and a caption at most) is the cover.
const COVER_TEXT = 80
const isCoverPage = (doc) =>
  !!doc?.querySelector("img, image") && (doc.body?.textContent.trim().length ?? 0) < COVER_TEXT

// A page that is only a picture (a cover, a plate, a full-page drawing)
// is laid out to fit the page and no more, whatever the book's own CSS
// sizes it by: wrappers in vh (foliate-js turns those into the window's
// height, not the page's), fixed heights or margins would push it past the
// page, onto a blank one after.
// - Paged (the html has .stashix-paged): the body is one page high and
//   spans the spread; the picture and its wrappers share what a caption
//   leaves, small pictures scaled up.
// - Scrolled: there is no page height to share, so the picture is as wide
//   as the text and foliate-js's cap at the view's height keeps it in view.
const PICTURE_PAGE_CSS = `
  body.stashix-picture-page { margin: 0 !important; padding: 0 !important; text-align: center !important; }
  .stashix-picture-wrap {
    width: 100% !important; height: auto !important; min-height: 0 !important;
    margin: 0 !important; padding: 0 !important; text-indent: 0 !important;
  }
  .stashix-picture {
    display: block !important; width: 100% !important; height: auto !important;
    margin: 0 auto !important; padding: 0 !important; object-fit: contain !important;
  }
  .stashix-paged body.stashix-picture-page {
    height: 100% !important; min-height: 0 !important; column-span: all !important;
    display: flex !important; flex-direction: column !important;
    align-items: center !important; justify-content: center !important;
  }
  .stashix-paged .stashix-picture-wrap {
    display: flex !important; flex-direction: column !important;
    align-items: center !important; justify-content: center !important;
    flex: 1 1 0 !important; max-height: 100% !important;
  }
  .stashix-paged .stashix-picture { flex: 1 1 0 !important; min-height: 0 !important; height: 100% !important; }
`

const fitPicturePage = (doc) => {
  const pics = [...doc.body.querySelectorAll("img, svg")].filter((el) => !el.parentElement.closest("svg"))
  if (pics.length !== 1) return
  const style = doc.createElement("style")
  style.textContent = PICTURE_PAGE_CSS
  doc.head.append(style)
  doc.body.classList.add("stashix-picture-page")
  pics[0].classList.add("stashix-picture")
  for (let el = pics[0].parentElement; el && el !== doc.body; el = el.parentElement) el.classList.add("stashix-picture-wrap")
}

// What foliate-js's MOBI reader needs of a File: its size, and slices it
// can read; the header and record table come first, then a record at a
// time as pages are laid out.
//
// Reads go by blocks of the file, each fetched once and kept (the latest
// MAX_BLOCKS of them): foliate-js reads a Kindle book a small record at a
// time, and a request per record made opening one a hundred round trips.
const BLOCK = 256 * 1024
const MAX_BLOCKS = 64

const remoteFile = async (url) => {
  const blocks = new Map()
  const fetchBlock = (i) => {
    const range = `bytes=${i * BLOCK}-${(i + 1) * BLOCK - 1}`
    const r = fetchOK(url, {headers: {Range: range}})
    return {response: r, data: r.then((res) => res.arrayBuffer())}
  }
  const keep = (i, data) => {
    blocks.set(i, data)
    data.catch(() => blocks.delete(i))
    if (blocks.size > MAX_BLOCKS) blocks.delete(blocks.keys().next().value)
  }
  // The first block also tells the file's size.
  const first = fetchBlock(0)
  const size = Number((await first.response).headers.get("content-range")?.split("/")[1])
  if (!size) throw new Error("no size")
  keep(0, first.data)

  const block = (i) => {
    let data = blocks.get(i)
    if (data) blocks.delete(i)
    else data = fetchBlock(i).data
    keep(i, data)
    return data
  }
  const read = async (start, end) => {
    const from = Math.floor(start / BLOCK)
    const parts = await Promise.all(
      Array.from({length: Math.floor((end - 1) / BLOCK) - from + 1}, (_, k) => block(from + k)),
    )
    const out = new Uint8Array(end - start)
    parts.forEach((buf, k) => {
      const at = (from + k) * BLOCK
      const lo = Math.max(start, at)
      const hi = Math.min(end, at + buf.byteLength)
      if (hi > lo) out.set(new Uint8Array(buf, lo - at, hi - lo), lo - start)
    })
    return out.buffer
  }

  const slice = (start = 0, end = size) => {
    start = Math.max(0, start)
    end = Math.min(size, end)
    return {
      size: Math.max(0, end - start),
      arrayBuffer: () => (end <= start ? Promise.resolve(new ArrayBuffer(0)) : read(start, end)),
    }
  }
  return {size, slice, name: url}
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
    ::highlight(stashix-tts) { background-color: ${t.scheme === "dark" ? "rgb(56 189 248 / 0.35)" : "rgb(250 204 21 / 0.45)"}; }
  `
}

const EpubReader = {
  mounted() {
    const d = this.el.dataset
    this.url = d.url
    this.start = Number(d.start) || 0
    this.startCfi = d.cfi || null
    this.startFraction = Number(d.fraction) || 0
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
    this.handleEvent("text:goto", (cmd) => (cmd.section != null ? this.gotoHit(cmd) : this.goto(cmd)))
    this.handleEvent("text:step", ({by}) => (by > 0 ? this.next() : this.prev()))
    this.handleEvent("text:view", (settings) => this.apply({...this.settings, ...settings}))
    this.handleEvent("text:search", ({query, server}) => (server ? this.clearSearch() : this.search(query)))
    this.handleEvent("annotations:all", ({items}) => this.setAnnotations(items))
    this.handleEvent("annotations:put", ({item}) => this.putAnnotation(item))
    this.handleEvent("annotations:remove", ({id}) => this.removeAnnotation(id))

    // id → {id, kind, color, locator, note}; drawn by CFI.
    this.annotations = new Map()
    this.bar = new AnnotationBar(this.el, (action, color) => this.barAction(action, color))

    // Read-aloud: the server's controls send "text:tts"; the hook says when
    // playback starts or stops, and which voices the browser has.
    this.aloud = new ReadAloud({
      next: () => this.ttsNext(),
      onState: ({playing}) => {
        if (!playing) this.ttsUnhighlight()
        this.pushEvent("tts_state", {playing})
      },
    })
    this.handleEvent("text:tts", (cmd) => this.tts(cmd))
    if (speechSupported()) {
      const voices = () => this.pushEvent("tts_voices", {voices: ReadAloud.voices()})
      speechSynthesis.addEventListener?.("voiceschanged", voices)
      this.onVoices = voices
      setTimeout(voices, 300)
    }

    this.onKey = (e) => this.key(e)
    this.onWheel = (e) => this.wheel(e)
    window.addEventListener("wheel", this.onWheel, {passive: false})
    window.addEventListener("keydown", this.onKey)

    // Taps on the page around the text (outside the chapter's frame) land
    // here; the view's shadow DOM retargets them to the view itself.
    let down = null
    this.el.addEventListener("pointerdown", (e) => { down = {x: e.clientX, y: e.clientY} })
    this.el.addEventListener("click", (e) => {
      if (!this.view || e.target !== this.view) return
      if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 8) return
      if (this.bar.visible) return this.bar.hide()
      this.tap(e.clientX)
    })

    this.open().catch((err) => {
      console.error("EpubReader:", err)
      this.pushEvent("failed", {})
    })
  },

  destroyed() {
    this.aloud.stop()
    if (this.onVoices) speechSynthesis.removeEventListener?.("voiceschanged", this.onVoices)
    this.bar.destroy()
    window.removeEventListener("keydown", this.onKey)
    window.removeEventListener("wheel", this.onWheel)
    clearTimeout(this.reportTimer)
    this.searchToken++
    this.view?.close()
    if (this.cover) URL.revokeObjectURL(this.cover.querySelector("img").src)
  },

  async open() {
    const {FootnoteHandler, Overlayer, CFI} = await loadFoliate()
    this.CFI = CFI
    this.book = await this.makeBook()
    this.view = document.createElement("foliate-view")
    this.view.className = "epub-view"
    this.el.append(this.view)
    this.note = this.buildNote()

    await this.view.open(this.book)
    this.view.addEventListener("relocate", (e) => this.relocated(e.detail))
    this.view.addEventListener("load", (e) => this.docLoaded(e.detail))

    // Highlights: drawn in each section's overlay as it is laid out; tapping
    // one brings up the bar for it.
    this.view.addEventListener("draw-annotation", (e) => {
      const {draw, annotation} = e.detail
      const item = this.annotations.get(annotation.id)
      if (!item) return
      if (item.kind === "highlight") draw(Overlayer.highlight, {color: HIGHLIGHT_COLORS[item.color] || HIGHLIGHT_COLORS.yellow})
      else draw(Overlayer.underline, {color: "#a1a1aa", width: 2})
    })
    this.view.addEventListener("create-overlay", () => this.drawAll())
    this.view.addEventListener("show-annotation", (e) => this.tappedAnnotation(e.detail))

    // Footnote links open in a small view of their own instead of jumping.
    this.notes = new FootnoteHandler()
    this.notes.addEventListener("before-render", (e) => this.styleNote(e.detail.view))
    this.notes.addEventListener("render", () => this.showNote())
    // A link followed from the keyboard is blurred, for the same reason (see
    // docLoaded): foliate-js refocuses the chapter's window after going.
    this.view.addEventListener("link", (e) => {
      e.detail.a?.blur()
      this.notes.handle(this.book, e)?.catch((err) => console.error(err))
    })
    // Links out of the book are confirmed first (the server asks).
    this.view.addEventListener("external-link", (e) => {
      e.preventDefault()
      e.detail.a?.blur()
      this.pushEvent("external_link", {url: e.detail.href_})
    })

    this.apply(this.settings)
    this.outline()

    // Resume at the spot the server has; progress from another app (no CFI)
    // and books saved before it kept one, at the same share of the book. A
    // book opened at its start opens on the cover; one resumed has it ready
    // for paging back.
    if (this.startCfi) await this.view.init({lastLocation: this.startCfi})
    else if (this.startFraction > 0) await this.view.goToFraction(this.startFraction)
    else if (this.start > 0 && this.total > 0) await this.view.goToFraction(this.start / this.total)
    else {
      await this.makeCover()
      this.showCover(true)
      return this.view.init({showTextStart: false})
    }
    this.makeCover()
  },

  // ── cover ─────────────────────────────────────────────────────────────

  // The cover page, when the book has a cover its first page doesn't show.
  async makeCover() {
    try {
      const blob = await this.book.getCover?.()
      if (!blob?.size) return
      const first = this.book.sections.find((s) => s.linear !== "no")
      if (isCoverPage(await first?.createDocument?.())) return
      const el = document.createElement("div")
      el.className = "epub-cover"
      el.hidden = true
      const img = document.createElement("img")
      img.alt = ""
      img.src = URL.createObjectURL(blob)
      el.append(img)
      // It covers the book's view, so its taps come here: turned like a page.
      el.addEventListener("click", (e) => this.tap(e.clientX))
      this.el.append(el)
      this.cover = el
      this.pushEvent("cover", {shown: false})
    } catch (err) {
      console.error("EpubReader cover", err)
    }
  },

  showCover(show) {
    if (!this.cover || this.cover.hidden === !show) return
    this.cover.hidden = !show
    // The server numbers the cover as page 1 and the book's pages after it.
    this.pushEvent("cover", {shown: show})
    if (show) this.pushEvent("scroll_end", {visible: false})
  },

  coverShown() {
    return this.cover ? !this.cover.hidden : false
  },

  // At the very start of the book's first page, where paging back shows
  // the cover.
  atStart() {
    const r = this.view.renderer
    const before = this.view.book.sections.slice(0, this.section?.current ?? 0)
    if (!before.every((s) => s.linear === "no")) return false
    return r.scrolled ? r.start <= 1 : r.atStart
  },

  async makeBook() {
    switch (this.el.dataset.format) {
      case "mobi":
      case "azw3":
      case "azw": {
        const [{MOBI}, fflate] = await Promise.all([foliate("mobi.js"), foliate("vendor/fflate.js")])
        return new MOBI({unzlib: fflate.unzlibSync}).open(await remoteFile(this.url))
      }
      case "fb2":
      case "fbz": {
        const {makeFB2} = await foliate("fb2.js")
        const blob = await fetchProgress(this.url, (loaded, total) => this.loadProgress(loaded, total))
        const book = await makeFB2(blob)
        book.getCover = () => fb2Cover(blob)
        return book
      }
      default:
        return this.makeEPUB()
    }
  },

  // At most a few reports a second, and always the last.
  loadProgress(loaded, total) {
    const now = Date.now()
    if (loaded < total && now - (this.progressAt || 0) < 200) return
    this.progressAt = now
    this.pushEvent("load_progress", {loaded, total})
  },

  async makeEPUB() {
    const {EPUB} = await foliate("epub.js")
    const {entries} = await fetchOK(this.url).then((r) => r.json())

    // Entry names are paths inside the zip; each segment is encoded on its own.
    const entryURL = (name) => `${this.url}/${name.split("/").map(encodeURIComponent).join("/")}`
    // Same contract as foliate-js's own zip loader: null for a missing entry.
    const loader = {
      loadText: (name) => (name in entries ? fetchOK(entryURL(name)).then((r) => r.text()) : null),
      loadBlob: (name, type) =>
        name in entries
          ? fetchOK(entryURL(name)).then((r) => r.blob()).then((b) => (type ? new Blob([b], {type}) : b))
          : null,
      getSize: (name) => entries[name] ?? 0,
    }
    return new EPUB(loader).init()
  },

  // ── settings ──────────────────────────────────────────────────────────

  apply(settings) {
    this.settings = settings
    if (!this.view?.renderer) return
    const r = this.view.renderer
    const paged = settings.layout !== "scroll"
    // Before the layout changes, so the page is laid out with it.
    for (const {doc} of r.getContents?.() ?? []) doc.documentElement.classList.toggle("stashix-paged", paged)
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
    this.visible = cfi
    this.fraction = fraction
    this.bar.hide()
    this.checkBookmark()
    if (this.coverShown() && !this.atStart()) this.showCover(false)
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
    if (this.coverShown()) return this.showCover(false)
    if (this.settings.layout !== "scroll" && this.lastSection() && this.view.renderer.atEnd) {
      this.pushEvent("paged_end", {})
      return
    }
    this.view.next()
  },

  // Back from the book's first page: the cover.
  prev() {
    if (!this.view || this.coverShown()) return
    if (this.cover && this.atStart()) return this.showCover(true)
    this.view.prev()
  },

  goto({page, target}) {
    if (!this.view) return
    this.showCover(false)
    if (target) this.view.goTo(target)
    else if (page != null && this.location?.total) this.view.goToFraction(Math.min(page / this.location.total, 0.9999))
  },

  // ── input ─────────────────────────────────────────────────────────────

  // Each chapter is its own document: keys and taps there never reach this
  // page, so they are wired up per document as it loads.
  docLoaded({doc, index}) {
    doc.documentElement.classList.toggle("stashix-paged", this.settings.layout !== "scroll")
    if (isCoverPage(doc)) fitPicturePage(doc)
    doc.addEventListener("keydown", this.onKey)
    doc.addEventListener("wheel", this.onWheel, {passive: false})
    // foliate-js scrolls whatever gains focus into view, a frame later. A
    // link pressed with the mouse would take focus just before its click
    // goes to the target, and be scrolled back to: pressing doesn't focus.
    doc.addEventListener("mousedown", (e) => e.target.closest?.("a[href]") && e.preventDefault())
    // A finished selection (mouse, touch handles or shift+arrows) brings up
    // the bar; clearing it takes the bar away.
    const selected = () => setTimeout(() => this.selected(doc, index), 10)
    doc.addEventListener("pointerup", selected)
    doc.addEventListener("keyup", (e) => e.shiftKey && selected())
    doc.addEventListener("selectionchange", () => {
      if (doc.getSelection()?.isCollapsed && this.bar.mode === "new") this.bar.hide()
    })
    let down = null
    doc.addEventListener("pointerdown", (e) => { down = {x: e.clientX, y: e.clientY} })
    doc.addEventListener("click", (e) => {
      if (e.defaultPrevented || e.target.closest?.("a[href]")) return
      if (down && Math.hypot(e.clientX - down.x, e.clientY - down.y) > 8) return
      if (!doc.defaultView.getSelection()?.isCollapsed) return
      const x = e.clientX + (doc.defaultView.frameElement?.getBoundingClientRect().left ?? 0)
      // A tap on a highlight shows its bar instead. foliate-js reports that
      // from its own click listener, which may run after this one: wait.
      setTimeout(() => {
        if (Date.now() - (this.annotationTap || 0) < 300) return
        if (this.bar.visible) return this.bar.hide()
        this.tap(x)
      })
    })
  },

  tap(x) {
    if (this.closeNote()) return
    const rect = this.el.getBoundingClientRect()
    const at = (x - rect.left) / rect.width
    if (this.settings.layout !== "scroll") {
      const rtl = this.book.dir === "rtl"
      if (at < ZONE_SIDE) return rtl ? this.next() : this.prev()
      if (at > 1 - ZONE_SIDE) return rtl ? this.prev() : this.next()
    }
    this.pushEvent("toggle_overlay", {})
  },

  // Ctrl (or ⌘) and the wheel step the text size, not the browser window's
  // zoom. Scrolling adds up (a trackpad pinch sends many small steps), a
  // size step for every 100 pixels or so.
  wheel(e) {
    if (!e.ctrlKey && !e.metaKey) return
    e.preventDefault()
    const delta = e.deltaY * (e.deltaMode === 1 ? 33 : 1)
    if (Math.sign(delta) !== Math.sign(this.wheelDelta || 0)) this.wheelDelta = 0
    this.wheelDelta += delta
    if (Math.abs(this.wheelDelta) < 100) return
    this.pushEvent("zoom", {by: this.wheelDelta < 0 ? 1 : -1})
    this.wheelDelta = 0
  },

  key(e) {
    if (e.target.closest?.("input, textarea, select, [contenteditable]")) return
    if (e.ctrlKey || e.metaKey || e.altKey || !this.view) return
    const rtl = this.book?.dir === "rtl"

    if (e.key === "Escape") return this.bar.hide() || this.closeNote() || this.pushEvent("close_panel", {})
    if (e.key === "+" || e.key === "=") this.pushEvent("zoom", {by: 1})
    else if (e.key === "-") this.pushEvent("zoom", {by: -1})
    else if (e.key === "0") this.pushEvent("zoom", {by: 0})
    else if (e.key === "ArrowRight") rtl ? this.prev() : this.next()
    else if (e.key === "ArrowLeft") rtl ? this.next() : this.prev()
    else if (e.key === "Home") this.view.goToFraction(0).then(() => this.showCover(true))
    else if (e.key === "End") this.goto({page: this.location?.total ?? 0})
    else if (this.settings.layout === "scroll" && !this.coverShown()) return
    else if (["ArrowDown", "PageDown", " "].includes(e.key)) e.shiftKey ? this.prev() : this.next()
    else if (["ArrowUp", "PageUp"].includes(e.key)) this.prev()
    else return
    e.preventDefault()
  },

  // ── annotations ───────────────────────────────────────────────────────

  setAnnotations(items) {
    for (const old of this.annotations.values()) this.undraw(old)
    this.annotations = new Map(items.map((a) => [a.id, a]))
    this.drawAll()
    this.checkBookmark()
  },

  putAnnotation(item) {
    const old = this.annotations.get(item.id)
    if (old) this.undraw(old)
    this.annotations.set(item.id, item)
    this.draw(item)
    this.checkBookmark()
  },

  removeAnnotation(id) {
    const old = this.annotations.get(id)
    if (!old) return
    this.annotations.delete(id)
    this.undraw(old)
    if (this.bar.annotation === id) this.bar.hide()
    this.checkBookmark()
  },

  // foliate-js keys drawings by CFI and hands back only that, so the CFI
  // carries the id along (see "draw-annotation").
  draw(item) {
    if (item.kind === "bookmark" || !item.locator?.cfi || !this.view) return
    this.view.addAnnotation({value: item.locator.cfi, id: item.id}).catch(() => {})
  },

  undraw(item) {
    if (item.kind !== "bookmark" && item.locator?.cfi) this.view?.deleteAnnotation({value: item.locator.cfi}).catch(() => {})
  },

  drawAll() {
    for (const item of this.annotations.values()) this.draw(item)
  },

  // Selected text in a section: the bar for a new highlight.
  selected(doc, index) {
    const sel = doc.getSelection()
    if (!sel || sel.isCollapsed || !sel.rangeCount) return
    const range = sel.getRangeAt(0)
    const text = range.toString().trim()
    if (!text) return
    this.pending = {doc, range, text, cfi: this.view.getCFI(index, range), index}
    this.bar.show(this.rangeRect(doc, range), {mode: "new"})
  },

  tappedAnnotation({value, range}) {
    const item = [...this.annotations.values()].find((a) => a.locator?.cfi === value)
    if (!item) return
    this.annotationTap = Date.now()
    this.pending = {range, text: range.toString().trim()}
    this.bar.show(this.rangeRect(range.startContainer.ownerDocument, range), {
      mode: "existing",
      annotation: item.id,
      color: item.color,
    })
  },

  // The range's box in this element's coordinates.
  rangeRect(doc, range) {
    const r = range.getBoundingClientRect()
    const frame = doc.defaultView.frameElement?.getBoundingClientRect() ?? {left: 0, top: 0}
    const host = this.el.getBoundingClientRect()
    return {left: r.left + frame.left - host.left, top: r.top + frame.top - host.top, width: r.width, height: r.height}
  },

  barAction(action, color) {
    const p = this.pending
    if (action === "copy") {
      if (p?.text) navigator.clipboard?.writeText(p.text).catch(() => {})
    } else if (this.bar.mode === "existing") {
      const id = this.bar.annotation
      if (action === "color") this.pushEvent("annotation_color", {id, color})
      else if (action === "note") this.pushEvent("annotation_edit", {id})
      else if (action === "delete") this.pushEvent("annotation_delete", {id})
    } else if (p?.cfi) {
      this.pushEvent("annotate", {
        kind: "highlight",
        color: color || "yellow",
        cfi: p.cfi,
        href: this.view.book.sections?.[p.index]?.id ?? null,
        text: p.text.slice(0, 10000),
        fraction: this.fraction ?? 0,
        edit: action === "note",
      })
      p.doc.getSelection()?.removeAllRanges()
    }
    this.bar.hide()
  },

  // Tells the server which bookmark (if any) is on the pages showing.
  checkBookmark() {
    if (!this.visible || !this.CFI) return
    const {collapse, compare} = this.CFI
    let here = null
    try {
      const start = collapse(this.visible)
      const end = collapse(this.visible, true)
      for (const a of this.annotations.values()) {
        if (a.kind !== "bookmark" || !a.locator?.cfi) continue
        // A bookmark is the range that showed when it was made: it is here
        // when that range overlaps the one showing now (reopened, the same
        // page can start a little further in).
        if (compare(collapse(a.locator.cfi, true), start) > 0 && compare(collapse(a.locator.cfi), end) < 0) {
          here = a.id
          break
        }
      }
    } catch (_) {}
    if (here !== this.bookmarkHere) {
      this.bookmarkHere = here
      this.pushEvent("bookmark_here", {id: here})
    }
  },

  // ── read-aloud ────────────────────────────────────────────────────────

  async tts({action, rate, voice, by}) {
    if (!this.view || !speechSupported()) return
    if (rate && rate !== this.aloud.rate) this.aloud.setRate(rate)
    if (voice !== undefined && (voice || null) !== this.aloud.voiceName) this.aloud.setVoice(voice)
    if (action === "play") {
      if (this.aloud.segments.length) return this.aloud.resume()
      // From the top of the page showing.
      await this.ttsInit()
      const range = this.view.lastLocation?.range
      this.aloud.play(this.ttsSegments(range ? this.view.tts.from(range) : this.view.tts.start()))
    } else if (action === "pause") this.aloud.pause()
    else if (action === "stop") this.aloud.stop()
    else if (action === "skip") this.aloud.skip(by)
  },

  ttsInit() {
    return this.view.initTTS("sentence", (range) => this.ttsHighlight(range))
  },

  ttsSegments(ssml) {
    if (!ssml) return []
    const tts = this.view.tts
    return ssmlSegments(ssml).map((s) => ({...s, onStart: () => s.mark && tts.setMark(s.mark)}))
  },

  // The next block of the section, or the first of the next section.
  async ttsNext() {
    const ssml = this.view?.tts?.next()
    if (ssml) return this.ttsSegments(ssml)
    if (!this.view || this.lastSection()) return null
    await this.view.renderer.nextSection()
    await this.ttsInit()
    return this.ttsSegments(this.view.tts.start()) || []
  },

  // The sentence being read: highlighted, and kept on screen (turning the
  // page when it runs over).
  ttsHighlight(range) {
    const win = range.startContainer.ownerDocument.defaultView
    if (win?.CSS?.highlights && win.Highlight) {
      win.CSS.highlights.set("stashix-tts", new win.Highlight(range))
      this.ttsWindow = win
    }
    this.view.renderer.scrollToAnchor(range)
  },

  ttsUnhighlight() {
    this.ttsWindow?.CSS?.highlights?.delete("stashix-tts")
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
        const section = node.href ? this.view.resolveNavigation(node.href)?.index : null
        items.push({
          title: (node.label || "").trim() || "—",
          target: node.href || null,
          section: Number.isInteger(section) ? section : null,
          depth,
        })
        walk(node.subitems, depth + 1)
      }
    }
    walk(this.book.toc, 0)
    this.pushEvent("outline", {items})
  },

  // ── search ────────────────────────────────────────────────────────────

  // EPUB is searched on the server, which lists hits as the n-th match in a
  // section; the matching follows foliate-js's, so searching just that
  // section here finds it. The section's matches are all marked.
  clearSearch() {
    this.searchToken++
    this.view?.clearSearch()
  },

  async gotoHit({section, n, query}) {
    const token = ++this.searchToken
    if (!this.view || !query) return
    this.showCover(false)
    let cfi = null
    let i = 0
    for await (const result of this.view.search({query, index: section})) {
      if (token !== this.searchToken) return
      if (result === "done") break
      if (result.cfi && i++ <= n) cfi = result.cfi
    }
    // No match there after all: the section's start.
    this.view.goTo(cfi ?? section)
  },

  // Other formats: foliate-js searches the whole book, section by section.
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
