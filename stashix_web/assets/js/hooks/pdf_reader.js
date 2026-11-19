/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import {exitReader} from "../reader_exit.js"
import {AnnotationBar, HIGHLIGHT_COLORS} from "../annotation_bar.js"
import {ReadAloud, sentences, supported as speechSupported} from "../read_aloud.js"

// PdfReader: the text reader's PDF view, drawn by PDF.js.
//
// The file is never downloaded whole: PDF.js reads it from /api/books/:id/file
// in byte ranges, fetching only what the pages on screen need. Every page gets
// a placeholder sized from page 1 (corrected when the page itself loads), and
// only pages near the viewport hold a canvas and a text layer; the rest are
// released as they scroll away.
//
// The server owns the chrome (bars, menus, contents and search panels) and
// sends commands as events ("text:goto", "text:view", "text:zoom",
// "text:search", shared with the EPUB hook); the hook reports back what it
// sees ("loaded", "outline", "page_changed", "search_results", "scroll_end",
// "set_overlay").
//
// Layouts: "scroll" (one column, scrolled natively), "paged" (one page) and
// "spread" (two pages side by side), turned with keys, taps or the server.
//
// Highlights: selecting text in a page's text layer brings up the
// annotation bar; a highlight is saved as the selection's boxes on that page
// in shares of the page ("rects"), drawn under the text layer, so they hold
// at any zoom.

const PDFJS = "/vendor/pdfjs/"
let pdfjsPromise = null

// A variable, not a literal, so esbuild leaves the import alone: PDF.js is
// served as is from /vendor and only fetched when a text PDF is opened.
const loadPdfjs = () => {
  const url = `${PDFJS}pdf.min.mjs`
  pdfjsPromise ||= import(url).then((lib) => {
    lib.GlobalWorkerOptions.workerSrc = `${PDFJS}pdf.worker.min.mjs`
    return lib
  })
  return pdfjsPromise
}

const GAP = 12              // px between pages in the scroll column
const READING_LINE = 0.35   // fraction of the viewport height that "is" the page
const REPORT_MS = 150
const BAR_HIDE_PX = 48      // scrolled down this far in one go tucks the bars away
const MIN_ZOOM = 0.5
const MAX_ZOOM = 4
const ZOOM_STEP = 1.2
const RERENDER_MS = 150
const ZONE_SIDE = 0.22      // paged layouts: side tap zones turn the page
const MAX_RESULTS = 500
const SNIPPET = 40          // characters of context each side of a search hit

// What an empty page shows until its drawing replaces it. A rerender keeps
// the old drawing up instead, so this only shows on pages not yet drawn.
const loading = () => {
  const el = document.createElement("div")
  el.className = "pdf-loading"
  el.setAttribute("role", "status")
  el.setAttribute("aria-label", "Loading page")
  el.innerHTML = `<span class="pdf-spinner animate-spin"></span>`
  return el
}

const PdfReader = {
  mounted() {
    const d = this.el.dataset
    this.url = d.url
    this.layout = d.layout
    this.fit = d.fit
    this.saver = d.saver === "true"
    this.zoom = 1
    this.page = Number(d.start) || 0
    this.count = 0
    this.slots = []          // placeholder per page: {el, w, h, state, task, ...}
    this.highlight = null    // search query marked in text layers
    this.searchToken = 0
    this.lastTop = 0
    this.travel = 0

    this.column = this.el.querySelector("[data-pdf-pages]")
    this.endEl = this.el.querySelector("[data-pdf-end]")
    this.setTheme(d.pageTheme)

    this.handleEvent("reader:exit", ({to}) => exitReader(this, to))
    this.handleEvent("text:goto", ({page, query}) => {
      if (query !== undefined) this.mark(query)
      this.goto(page)
    })
    this.handleEvent("text:step", ({by}) => this.step(by))
    this.handleEvent("text:view", (view) => this.setView(view))
    this.handleEvent("text:zoom", ({by}) => this.setZoom(by === 0 ? 1 : this.zoom * (by > 0 ? ZOOM_STEP : 1 / ZOOM_STEP)))
    // The server searches the PDF when poppler can read it; this only marks
    // the hits then. Otherwise it reads each page's text here.
    this.handleEvent("text:search", ({query, server}) => {
      if (!server) return this.search(query)
      this.searchToken++
      this.mark(query)
    })
    this.handleEvent("annotations:all", ({items}) => {
      this.annotations = new Map(items.map((a) => [a.id, a]))
      this.slots.forEach((s) => this.drawAnnotations(s))
    })
    this.handleEvent("annotations:put", ({item}) => {
      this.annotations.set(item.id, item)
      this.redrawPage(item.locator?.page)
    })
    this.handleEvent("annotations:remove", ({id}) => {
      const page = this.annotations.get(id)?.locator?.page
      this.annotations.delete(id)
      if (this.bar.annotation === id) this.bar.hide()
      this.redrawPage(page)
    })
    this.annotations = new Map()
    this.bar = new AnnotationBar(this.el, (action, color) => this.barAction(action, color))
    // Read-aloud: page by page from the text layer's content; the page being
    // read is brought into view as it starts.
    this.aloud = new ReadAloud({
      next: () => this.ttsPage(this.ttsAt + 1),
      onState: ({playing}) => this.pushEvent("tts_state", {playing}),
    })
    this.handleEvent("text:tts", (cmd) => this.tts(cmd))
    if (speechSupported()) {
      this.onVoices = () => this.pushEvent("tts_voices", {voices: ReadAloud.voices()})
      speechSynthesis.addEventListener?.("voiceschanged", this.onVoices)
      setTimeout(this.onVoices, 300)
    }
    this.onSelect = (e) => (e.type === "keyup" && !e.shiftKey ? null : setTimeout(() => this.selected(), 10))
    this.el.addEventListener("pointerup", this.onSelect)
    this.el.addEventListener("keyup", this.onSelect)

    this.onScroll = () => {
      if (this.frame == null) this.frame = requestAnimationFrame(() => this.scrolled())
    }
    this.onKey = (e) => this.key(e)
    this.onWheel = (e) => this.wheel(e)
    window.addEventListener("wheel", this.onWheel, {passive: false})
    this.onPointerDown = (e) => { this.down = {x: e.clientX, y: e.clientY} }
    this.onClick = (e) => this.click(e)
    this.el.addEventListener("scroll", this.onScroll, {passive: true})
    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("click", this.onClick)
    window.addEventListener("keydown", this.onKey)

    this.resizeObserver = new ResizeObserver(() => {
      clearTimeout(this.resizeTimer)
      this.resizeTimer = setTimeout(() => this.relayout(), 120)
    })

    this.open().catch((err) => {
      console.error("PdfReader:", err)
      this.pushEvent("failed", {})
    })
  },

  destroyed() {
    this.aloud.stop()
    if (this.onVoices) speechSynthesis.removeEventListener?.("voiceschanged", this.onVoices)
    this.bar.destroy()
    this.el.removeEventListener("pointerup", this.onSelect)
    this.el.removeEventListener("keyup", this.onSelect)
    this.el.removeEventListener("scroll", this.onScroll)
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("click", this.onClick)
    window.removeEventListener("keydown", this.onKey)
    window.removeEventListener("wheel", this.onWheel)
    cancelAnimationFrame(this.wheelFrame)
    this.resizeObserver.disconnect()
    this.pageObserver?.disconnect()
    this.endObserver?.disconnect()
    clearTimeout(this.reportTimer)
    clearTimeout(this.resizeTimer)
    clearTimeout(this.rerenderTimer)
    if (this.frame != null) cancelAnimationFrame(this.frame)
    this.searchToken++
    this.slots.forEach((s) => this.release(s))
    this.loadingTask?.destroy()
  },

  async open() {
    this.lib = await loadPdfjs()
    this.loadingTask = this.lib.getDocument({
      url: this.url,
      // Ranges only: no background download of the rest of the file.
      disableAutoFetch: true,
      disableStream: true,
      rangeChunkSize: 128 * 1024,
      standardFontDataUrl: `${PDFJS}standard_fonts/`,
      cMapUrl: `${PDFJS}cmaps/`,
      cMapPacked: true,
      wasmUrl: `${PDFJS}wasm/`,
      iccUrl: `${PDFJS}iccs/`,
      isEvalSupported: false,
    })
    this.doc = await this.loadingTask.promise
    this.count = this.doc.numPages
    this.page = Math.min(this.page, this.count - 1)

    const first = await this.doc.getPage(1)
    const {width, height} = first.getViewport({scale: 1})
    this.build(width, height)
    this.pushEvent("loaded", {page_count: this.count})
    this.outline()
  },

  // One placeholder per page, all sized like page 1 until they load.
  build(width, height) {
    this.column.textContent = ""
    this.slots = Array.from({length: this.count}, (_, i) => {
      const el = document.createElement("div")
      el.className = "pdf-page"
      el.dataset.page = i
      el.appendChild(loading())
      this.column.appendChild(el)
      return {el, index: i, w: width, h: height, state: "empty"}
    })

    // Generous margin while scrolling so the next pages are ready; none in
    // data saver, which only renders what is on screen.
    this.pageObserver = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        const slot = this.slots[Number(entry.target.dataset.page)]
        slot.near = entry.isIntersecting
        if (entry.isIntersecting) this.render(slot)
        else this.release(slot)
      }
    }, {root: this.el, rootMargin: this.saver ? "0px" : "100% 0px"})
    this.slots.forEach((s) => this.pageObserver.observe(s.el))

    this.endObserver = new IntersectionObserver(([entry]) => {
      if (this.layout === "scroll") this.pushEvent("scroll_end", {visible: entry.isIntersecting})
    }, {root: this.el, threshold: 0.6})
    this.endObserver.observe(this.endEl)

    this.resizeObserver.observe(this.el)
    this.relayout()
    this.goto(this.page)
  },

  // ── layout ────────────────────────────────────────────────────────────

  setView({layout, fit, theme}) {
    if (theme) this.setTheme(theme)
    if ((layout && layout !== this.layout) || (fit && fit !== this.fit)) {
      this.layout = layout || this.layout
      this.fit = fit || this.fit
      this.relayout()
      this.goto(this.page)
    }
  },

  setTheme(theme) {
    this.el.dataset.pageTheme = theme
  },

  // Zooms about a point on screen (the wheel's, else the middle of the
  // view), keeping the spot of the page under it where it is.
  setZoom(zoom, x, y) {
    zoom = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, zoom))
    if (zoom === this.zoom) return
    const view = this.el.getBoundingClientRect()
    x ??= view.left + view.width / 2
    y ??= view.top + view.height / 2
    const under = document.elementFromPoint(x, y)?.closest(".pdf-page")
    const slot = (under && this.slots[Number(under.dataset.page)]) || this.slots[this.page]
    const before = slot?.el.getBoundingClientRect()

    this.zoom = zoom
    this.relayout()
    if (!before?.width) return this.goto(this.page)

    const fx = (x - before.left) / before.width
    const fy = (y - before.top) / before.height
    const after = slot.el.getBoundingClientRect()
    this.el.scrollLeft += after.left + fx * after.width - x
    this.el.scrollTop += after.top + fy * after.height - y
    this.lastTop = this.el.scrollTop
  },

  // Ctrl (or ⌘) and the wheel zoom the PDF, not the browser window. A
  // trackpad pinch sends the same, in many small steps: they add up and
  // the pages are laid out once a frame.
  wheel(e) {
    if (!e.ctrlKey && !e.metaKey) return
    e.preventDefault()
    const delta = e.deltaY * (e.deltaMode === 1 ? 33 : 1)
    this.wheelFactor = (this.wheelFactor || 1) * Math.exp(-delta / 500)
    this.wheelAt = [e.clientX, e.clientY]
    this.wheelFrame ||= requestAnimationFrame(() => {
      this.wheelFrame = null
      this.setZoom(this.zoom * this.wheelFactor, ...this.wheelAt)
      this.wheelFactor = 1
    })
  },

  // Page scale from the fit mode and zoom; page 1 sets it for the whole book
  // so pages keep one size.
  scaleFor() {
    const base = this.slots[0]
    if (!base) return 1
    const pad = this.el.clientWidth < 640 ? 8 : 32
    const across = this.layout === "spread" ? 2 : 1
    const width = (this.el.clientWidth - pad * 2 - (across - 1) * GAP) / across
    const height = this.el.clientHeight - pad * 2
    const fitWidth = width / base.w
    const scale = this.fit === "page" ? Math.min(fitWidth, height / base.h) : fitWidth
    return Math.max(0.1, scale * this.zoom)
  },

  relayout() {
    if (!this.slots.length) return
    const scale = this.scaleFor()
    const changed = scale !== this.scale
    this.scale = scale
    this.el.dataset.layout = this.layout
    this.column.style.setProperty("--total-scale-factor", scale)
    this.slots.forEach((s) => this.size(s))
    this.showPaged()
    // Rendered pages stretch to the new size meanwhile (canvas, text and
    // highlights all follow the page's box); they are drawn sharp again
    // once the zoom settles, not on every step of a pinch.
    if (changed) {
      clearTimeout(this.rerenderTimer)
      this.rerenderTimer = setTimeout(() => this.slots.forEach((s) => s.state !== "empty" && this.rerender(s)), RERENDER_MS)
    }
  },

  size(slot) {
    slot.el.style.width = `${Math.floor(slot.w * this.scale)}px`
    slot.el.style.height = `${Math.floor(slot.h * this.scale)}px`
  },

  // Paged layouts show the current page (and its neighbour in a spread).
  showPaged() {
    const paged = this.layout !== "scroll"
    const [a, b] = this.visiblePages()
    this.slots.forEach((s) => {
      s.el.hidden = paged && s.index !== a && s.index !== b
    })
  },

  visiblePages() {
    if (this.layout === "spread") {
      const a = this.page - (this.page % 2)
      return [a, a + 1 < this.count ? a + 1 : null]
    }
    return [this.page, null]
  },

  // ── rendering ─────────────────────────────────────────────────────────

  async render(slot) {
    if (slot.state !== "empty" || slot.el.hidden) return
    slot.state = "rendering"
    const scale = this.scale
    // A rerender starts a new run while the old one may still be awaiting.
    const run = (slot.run = (slot.run || 0) + 1)

    try {
      const page = slot.pdfPage || (slot.pdfPage = await this.doc.getPage(slot.index + 1))
      const raw = page.getViewport({scale: 1})
      if (raw.width !== slot.w || raw.height !== slot.h) {
        slot.w = raw.width
        slot.h = raw.height
        this.size(slot)
      }
      if (slot.run !== run || scale !== this.scale) return

      const viewport = page.getViewport({scale})
      const ratio = this.saver ? 1 : Math.min(window.devicePixelRatio || 1, 2)
      const canvas = document.createElement("canvas")
      canvas.width = Math.floor(viewport.width * ratio)
      canvas.height = Math.floor(viewport.height * ratio)
      canvas.className = "pdf-canvas"

      slot.task = page.render({
        canvasContext: canvas.getContext("2d"),
        viewport,
        transform: ratio !== 1 ? [ratio, 0, 0, ratio, 0, 0] : null,
      })
      await slot.task.promise
      if (slot.run !== run) return

      const text = document.createElement("div")
      text.className = "textLayer"
      slot.textLayer = new this.lib.TextLayer({
        textContentSource: page.streamTextContent({includeMarkedContent: true, disableNormalization: true}),
        container: text,
        viewport,
      })

      const links = await this.linkLayer(page, viewport)
      if (slot.run !== run) return

      slot.annots = document.createElement("div")
      slot.annots.className = "pdf-annots"
      const old = slot.el.querySelector("canvas")
      slot.el.replaceChildren(canvas, slot.annots, text, links)
      if (old) old.width = old.height = 0
      slot.state = "done"
      this.drawAnnotations(slot)
      await slot.textLayer.render()
      this.markSlot(slot)
    } catch (err) {
      if (err?.name !== "RenderingCancelledException") console.error("PdfReader page", slot.index + 1, err)
      if (slot.run === run && slot.state === "rendering") slot.state = "empty"
    }
  },

  // The page's links, over its text. Positions are shares of the page, so
  // they follow it through zooms like the highlights. Links out of the book
  // are confirmed first (the server asks); links inside it go to their page.
  async linkLayer(page, viewport) {
    const layer = document.createElement("div")
    layer.className = "pdf-links"
    const annotations = await page.getAnnotations({intent: "display"}).catch(() => [])
    // PDF space to the page's: viewport.transform, applied to both corners.
    const [ta, tb, tc, td, te, tf] = viewport.transform
    const point = (x, y) => [ta * x + tc * y + te, tb * x + td * y + tf]
    for (const a of annotations) {
      const url = a.url || a.unsafeUrl
      if (a.subtype !== "Link" || (!url && a.dest == null) || a.rect?.length !== 4) continue
      const [x1, y1] = point(a.rect[0], a.rect[1])
      const [x2, y2] = point(a.rect[2], a.rect[3])
      const share = (v, size) => `${(v / size) * 100}%`
      const link = document.createElement("a")
      link.className = "pdf-link"
      link.tabIndex = 0
      link.setAttribute("role", "link")
      if (url) link.title = url
      link.style.left = share(Math.min(x1, x2), viewport.width)
      link.style.top = share(Math.min(y1, y2), viewport.height)
      link.style.width = share(Math.abs(x2 - x1), viewport.width)
      link.style.height = share(Math.abs(y2 - y1), viewport.height)
      const follow = (e) => {
        e.preventDefault()
        this.followLink(url, a.dest)
      }
      link.addEventListener("click", follow)
      link.addEventListener("keydown", (e) => e.key === "Enter" && follow(e))
      layer.appendChild(link)
    }
    return layer
  },

  async followLink(url, dest) {
    if (url) return this.pushEvent("external_link", {url})
    try {
      const explicit = typeof dest === "string" ? await this.doc.getDestination(dest) : dest
      const ref = explicit?.[0]
      if (ref == null) return
      this.goto(typeof ref === "object" ? await this.doc.getPageIndex(ref) : ref)
    } catch (err) {
      console.error("PdfReader link", err)
    }
  },

  // Draws the page again at the current scale. What it shows now stays up,
  // stretched, until the new drawing replaces it.
  rerender(slot) {
    if (!slot.near) return this.release(slot)
    slot.task?.cancel()
    slot.task = null
    slot.textLayer?.cancel()
    slot.textLayer = null
    slot.state = "empty"
    this.render(slot)
  },

  // Frees the canvas (its pixels are the memory that adds up) and the text.
  release(slot) {
    slot.task?.cancel()
    slot.task = null
    slot.textLayer?.cancel()
    slot.textLayer = null
    const canvas = slot.el.querySelector("canvas")
    if (canvas) canvas.width = canvas.height = 0
    slot.el.replaceChildren(loading())
    slot.annots = null
    slot.pdfPage?.cleanup()
    slot.run = (slot.run || 0) + 1
    slot.state = "empty"
  },

  // ── position ──────────────────────────────────────────────────────────

  goto(page) {
    if (!this.count) {
      this.page = page
      return
    }
    this.page = Math.max(0, Math.min(page, this.count - 1))
    if (this.layout === "scroll") {
      const slot = this.slots[this.page]
      this.el.scrollTop = slot.el.offsetTop - GAP
      this.lastTop = this.el.scrollTop
    } else {
      this.showPaged()
      this.el.scrollTop = 0
      this.el.scrollLeft = 0
      this.visiblePages().forEach((i) => i != null && this.render(this.slots[i]))
    }
    this.report()
  },

  // Paged layouts: one page or one spread forward or back. Past the last
  // page the server shows the end card; before the first nothing happens.
  step(by) {
    if (this.layout === "scroll") {
      this.el.scrollBy({top: by * this.el.clientHeight * 0.85, behavior: "smooth"})
      return
    }
    const size = this.layout === "spread" ? 2 : 1
    const next = this.visiblePages()[0] + by * size
    if (next >= this.count) this.pushEvent("paged_end", {})
    else if (next >= 0) this.goto(next)
  },

  scrolled() {
    this.frame = null
    if (this.layout !== "scroll") return
    const top = this.el.scrollTop

    // Bars hide on a deliberate scroll down and come back on any scroll up.
    const delta = top - this.lastTop
    this.lastTop = top
    this.travel = delta > 0 ? Math.max(this.travel, 0) + delta : 0
    const barsShown = this.el.dataset.overlay === "true"
    if (barsShown && this.travel > BAR_HIDE_PX) {
      this.pushEvent("set_overlay", {visible: false})
      this.el.dataset.overlay = "false"
    } else if (!barsShown && delta < -8) {
      this.pushEvent("set_overlay", {visible: true})
      this.el.dataset.overlay = "true"
    }

    const page = this.pageAt(top + this.el.clientHeight * READING_LINE)
    if (page !== this.page) {
      this.page = page
      this.report()
    }
  },

  report() {
    clearTimeout(this.reportTimer)
    this.reportTimer = setTimeout(() => this.pushEvent("page_changed", {page: this.page}), REPORT_MS)
  },

  // Last page whose top edge sits above y (the column is sorted).
  pageAt(y) {
    let lo = 0, hi = this.slots.length - 1
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1
      if (this.slots[mid].el.offsetTop <= y) lo = mid
      else hi = mid - 1
    }
    return lo
  },

  // ── input ─────────────────────────────────────────────────────────────

  key(e) {
    if (e.target.closest?.("input, textarea, select, [contenteditable]")) return
    if (e.ctrlKey || e.metaKey || e.altKey) return
    const scroll = this.layout === "scroll"

    if (e.key === "+" || e.key === "=") this.setZoom(this.zoom * ZOOM_STEP)
    else if (e.key === "-") this.setZoom(this.zoom / ZOOM_STEP)
    else if (e.key === "0") this.setZoom(1)
    else if (e.key === "ArrowRight") scroll ? this.goto(this.page + 1) : this.step(1)
    else if (e.key === "ArrowLeft") scroll ? this.goto(this.page - 1) : this.step(-1)
    else if (e.key === "Home") this.goto(0)
    else if (e.key === "End") this.goto(this.count - 1)
    else if (e.key === "Escape") this.bar.hide() || this.pushEvent("close_panel", {})
    // Scroll layout: arrows, space and page keys scroll the column natively.
    else if (!scroll && ["ArrowDown", "PageDown", " "].includes(e.key)) this.step(e.shiftKey ? -1 : 1)
    else if (!scroll && ["ArrowUp", "PageUp"].includes(e.key)) this.step(-1)
    else if (scroll && e.target === document.body && ["ArrowDown", "ArrowUp", "PageDown", "PageUp", " "].includes(e.key)) {
      // Keys go to the body until the column is focused; send them on.
      this.el.focus({preventScroll: true})
      return
    } else return
    e.preventDefault()
  },

  // A plain tap (not a drag, not a text selection) toggles the bars; in the
  // paged layouts the sides turn the page.
  click(e) {
    if (e.target.closest("button, a, input, .annot-bar")) return
    if (this.down && Math.hypot(e.clientX - this.down.x, e.clientY - this.down.y) > 8) return
    if (!window.getSelection()?.isCollapsed) return
    if (this.bar.hide()) return
    if (this.tappedAnnotation(e)) return

    if (this.layout !== "scroll") {
      const x = e.clientX / this.el.clientWidth
      if (x < ZONE_SIDE) return this.step(-1)
      if (x > 1 - ZONE_SIDE) return this.step(1)
    }
    this.pushEvent("toggle_overlay", {})
  },

  // ── read-aloud ────────────────────────────────────────────────────────

  async tts({action, rate, voice, by}) {
    if (!this.doc || !speechSupported()) return
    if (rate && rate !== this.aloud.rate) this.aloud.setRate(rate)
    if (voice !== undefined && (voice || null) !== this.aloud.voiceName) this.aloud.setVoice(voice)
    if (action === "play") {
      if (this.aloud.segments.length) return this.aloud.resume()
      this.aloud.play(await this.ttsPage(this.page))
    } else if (action === "pause") this.aloud.pause()
    else if (action === "stop") this.aloud.stop()
    else if (action === "skip") this.aloud.skip(by)
  },

  // A page's sentences, from the next page with any text; null past the end.
  async ttsPage(page) {
    for (let i = page; i < this.count; i++) {
      const content = await (await this.doc.getPage(i + 1)).getTextContent()
      const text = content.items.map((it) => (it.str || "") + (it.hasEOL ? " " : "")).join("")
      const list = sentences(text, document.documentElement.lang)
      if (!list.length) continue
      this.ttsAt = i
      return list.map((t, n) => ({text: t, onStart: n === 0 ? () => this.ttsShow(i) : null}))
    }
    return null
  },

  ttsShow(page) {
    const [a, b] = this.visiblePages()
    if (this.layout === "scroll" ? page !== this.page : page !== a && page !== b) this.goto(page)
  },

  // ── annotations ───────────────────────────────────────────────────────

  drawAnnotations(slot) {
    if (!slot?.annots) return
    slot.annots.replaceChildren()
    for (const a of this.annotations.values()) {
      if (a.locator?.page !== slot.index || !a.locator.rects) continue
      const color = a.kind === "highlight" ? HIGHLIGHT_COLORS[a.color] || HIGHLIGHT_COLORS.yellow : null
      for (const [x, y, w, h] of a.locator.rects) {
        const box = document.createElement("div")
        box.className = color ? "pdf-annot" : "pdf-annot pdf-annot-note"
        box.style.cssText = `left:${x * 100}%;top:${y * 100}%;width:${w * 100}%;height:${h * 100}%;${color ? `background:${color}` : ""}`
        slot.annots.append(box)
      }
    }
  },

  redrawPage(page) {
    if (Number.isInteger(page)) this.drawAnnotations(this.slots[page])
  },

  // The page a node is on, by its slot.
  slotOf(node) {
    const el = (node?.nodeType === 1 ? node : node?.parentElement)?.closest?.(".pdf-page")
    return el ? this.slots[Number(el.dataset.page)] : null
  },

  // A selection in one page's text: the bar for a new highlight. Only the
  // part on the page it starts on counts.
  selected() {
    const sel = window.getSelection()
    if (!sel || sel.isCollapsed || !sel.rangeCount) return
    const range = sel.getRangeAt(0)
    const slot = this.slotOf(range.startContainer)
    if (!slot || !this.el.contains(range.startContainer)) return
    const page = slot.el.getBoundingClientRect()
    const rects = [...range.getClientRects()]
      .filter((r) => r.width > 1 && r.height > 1 && r.bottom > page.top && r.top < page.bottom && r.right > page.left && r.left < page.right)
      .slice(0, 200)
      .map((r) => [(r.left - page.left) / page.width, (r.top - page.top) / page.height, r.width / page.width, r.height / page.height])
    const text = range.toString().trim()
    if (!rects.length || !text) return
    this.pending = {page: slot.index, rects, text}
    this.bar.show(this.boxOf(range.getBoundingClientRect()), {mode: "new"})
  },

  // A tap on a highlight: the bar for it.
  tappedAnnotation(e) {
    const slot = this.slotOf(e.target)
    if (!slot) return false
    const page = slot.el.getBoundingClientRect()
    const x = (e.clientX - page.left) / page.width
    const y = (e.clientY - page.top) / page.height
    const hit = [...this.annotations.values()].find(
      (a) => a.locator?.page === slot.index && a.locator.rects?.some(([rx, ry, rw, rh]) => x >= rx && x <= rx + rw && y >= ry && y <= ry + rh),
    )
    if (!hit) return false
    const [rx, ry, rw, rh] = hit.locator.rects[0]
    this.pending = {text: null}
    this.bar.show(this.boxOf({left: page.left + rx * page.width, top: page.top + ry * page.height, width: rw * page.width, height: rh * page.height}), {
      mode: "existing",
      annotation: hit.id,
      color: hit.color,
      copy: false,
    })
    return true
  },

  // A client rect relative to this element's box.
  boxOf(r) {
    const host = this.el.getBoundingClientRect()
    return {left: r.left - host.left, top: r.top - host.top, width: r.width, height: r.height}
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
    } else if (p?.rects) {
      this.pushEvent("annotate", {
        kind: "highlight",
        color: color || "yellow",
        page: p.page,
        rects: p.rects,
        text: p.text.slice(0, 10000),
        fraction: this.count > 1 ? p.page / (this.count - 1) : 0,
        edit: action === "note",
      })
      window.getSelection()?.removeAllRanges()
    }
    this.bar.hide()
  },

  // ── contents ──────────────────────────────────────────────────────────

  async outline() {
    const items = []
    const walk = async (nodes, depth) => {
      for (const node of nodes || []) {
        if (items.length >= 2000) return
        items.push({title: node.title, page: await this.destPage(node.dest), depth})
        await walk(node.items, depth + 1)
      }
    }
    try {
      await walk(await this.doc.getOutline(), 0)
    } catch (err) {
      console.error("PdfReader outline", err)
    }
    this.pushEvent("outline", {items})
  },

  async destPage(dest) {
    try {
      const explicit = typeof dest === "string" ? await this.doc.getDestination(dest) : dest
      if (!Array.isArray(explicit)) return null
      const ref = explicit[0]
      return typeof ref === "number" ? ref : await this.doc.getPageIndex(ref)
    } catch (_) {
      return null
    }
  },

  // ── search ────────────────────────────────────────────────────────────

  // Reads each page's text in turn (fetching the ranges it needs) and sends
  // hits back a page batch at a time. A new query cancels the running one.
  async search(query) {
    const token = ++this.searchToken
    this.mark(query)
    const needle = (query || "").trim().toLocaleLowerCase()
    if (!needle || !this.doc) return

    let found = 0
    let batch = []
    for (let i = 0; i < this.count && found < MAX_RESULTS; i++) {
      const page = await this.doc.getPage(i + 1)
      const content = await page.getTextContent()
      if (token !== this.searchToken) return
      const text = content.items.map((item) => item.str + (item.hasEOL ? " " : "")).join("")
      const lower = text.toLocaleLowerCase()
      for (let at = lower.indexOf(needle); at !== -1 && found < MAX_RESULTS; at = lower.indexOf(needle, at + needle.length)) {
        batch.push({page: i, before: text.slice(Math.max(0, at - SNIPPET), at), match: text.slice(at, at + needle.length), after: text.slice(at + needle.length, at + needle.length + SNIPPET)})
        found++
      }
      if (batch.length >= 20 || i % 25 === 24) {
        this.pushEvent("search_results", {query, results: batch, scanned: i + 1, done: false})
        batch = []
      }
    }
    if (token === this.searchToken) this.pushEvent("search_results", {query, results: batch, scanned: this.count, done: true})
  },

  mark(query) {
    this.highlight = (query || "").trim().toLocaleLowerCase() || null
    this.slots.forEach((s) => s.state === "done" && this.markSlot(s))
  },

  // Wraps each hit inside the text-layer runs in a .pdf-hit span. A run is
  // drawn in one font scaled to its width, so the wrapped part lines up with
  // the canvas. A hit split across two runs is not marked; the page is still
  // found.
  markSlot(slot) {
    const needle = this.highlight
    for (const span of slot.el.querySelectorAll(".textLayer span:not(.pdf-hit):not(.markedContent)")) {
      const text = span.dataset.text ?? span.textContent
      if (span.dataset.text !== undefined) {
        span.textContent = text
        delete span.dataset.text
      }
      if (!needle) continue
      const lower = text.toLocaleLowerCase()
      if (!lower.includes(needle)) continue

      const parts = []
      let from = 0
      for (let at = lower.indexOf(needle); at !== -1; at = lower.indexOf(needle, at + needle.length)) {
        parts.push(document.createTextNode(text.slice(from, at)))
        const hit = document.createElement("span")
        hit.className = "pdf-hit"
        hit.textContent = text.slice(at, at + needle.length)
        parts.push(hit)
        from = at + needle.length
      }
      parts.push(document.createTextNode(text.slice(from)))
      span.dataset.text = text
      span.replaceChildren(...parts)
    }
  },
}

export default PdfReader
