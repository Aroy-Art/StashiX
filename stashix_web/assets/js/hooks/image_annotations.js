/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import {AnnotationBar, HIGHLIGHT_COLORS} from "../annotation_bar.js"

// ImageAnnotations: region highlights in the comic reader.
//
// A layer over the reading area. Its boxes follow the page images they sit
// on (single, facing pages or the webtoon strip, at any fit, zoom or
// scroll): each frame they are placed from the images' boxes, since
// ReaderZoom moves the pages with a transform this layer never hears about.
// Regions are stored as [x, y, w, h] shares of the page.
//
// Outside mark mode the layer lets every pointer through, so taps still turn
// pages. In mark mode (data-mark="true", the highlighter button) it takes
// them: drag a box on a page, then pick a colour or a note from the bar;
// tap a region to recolour, note or delete it. Escape leaves the mode.
//
// The server owns the list (StashixWeb.Live.ReaderAnnotations) and sends
// "annotations:all" / "annotations:put" / "annotations:remove".

const MIN_DRAG = 12   // px: anything smaller is a tap

const ImageAnnotations = {
  mounted() {
    this.annotations = new Map()
    this.boxes = new Map()   // id -> element
    this.bar = new AnnotationBar(this.el, (action, color) => this.barAction(action, color))
    this.draft = document.createElement("div")
    this.draft.className = "img-annot img-annot-draft"
    this.draft.hidden = true
    this.el.append(this.draft)

    this.handleEvent("annotations:all", ({items}) => {
      this.annotations = new Map(items.map((a) => [a.id, a]))
      this.rebuild()
    })
    this.handleEvent("annotations:put", ({item}) => {
      this.annotations.set(item.id, item)
      this.rebuild()
    })
    this.handleEvent("annotations:remove", ({id}) => {
      this.annotations.delete(id)
      if (this.bar.annotation === id) this.bar.hide()
      this.rebuild()
    })
    this.pushEvent("annotations_load", {})

    this.onDown = (e) => this.down(e)
    this.onMove = (e) => this.move(e)
    this.onUp = (e) => this.up(e)
    this.onKey = (e) => {
      if (e.key === "Escape" && this.marking()) {
        if (!this.bar.hide()) this.pushEvent("toggle_mark", {})
        e.stopPropagation()
      }
    }
    this.el.addEventListener("pointerdown", this.onDown)
    this.el.addEventListener("pointermove", this.onMove)
    this.el.addEventListener("pointerup", this.onUp)
    this.el.addEventListener("pointercancel", this.onUp)
    window.addEventListener("keydown", this.onKey, true)

    this.frame = requestAnimationFrame(() => this.tick())
  },

  updated() {
    if (!this.marking()) {
      this.bar.hide()
      this.draft.hidden = true
      this.drag = null
    }
  },

  destroyed() {
    cancelAnimationFrame(this.frame)
    this.bar.destroy()
    window.removeEventListener("keydown", this.onKey, true)
  },

  marking() {
    return this.el.dataset.mark === "true"
  },

  // ── drawing ───────────────────────────────────────────────────────────

  rebuild() {
    for (const el of this.boxes.values()) el.remove()
    this.boxes.clear()
    for (const a of this.annotations.values()) {
      if (!a.locator?.rect) continue
      const el = document.createElement("div")
      el.className = a.kind === "highlight" ? "img-annot" : "img-annot img-annot-note"
      el.style.setProperty("--c", HIGHLIGHT_COLORS[a.color] || HIGHLIGHT_COLORS.yellow)
      el.dataset.id = a.id
      el.hidden = true
      this.el.append(el)
      this.boxes.set(a.id, el)
    }
  },

  // The page images showing, by page index.
  pages() {
    const imgs = document.querySelectorAll("#reader-pages img[data-page], #webtoon-strip img[data-page]")
    const map = new Map()
    for (const img of imgs) if (img.naturalWidth && img.style.opacity !== "0") map.set(Number(img.dataset.page), img)
    return map
  },

  tick() {
    this.frame = requestAnimationFrame(() => this.tick())
    this.el.classList.toggle("img-annot-marking", this.marking())
    if (!this.boxes.size) return
    const host = this.el.getBoundingClientRect()
    const pages = this.pages()
    for (const [id, el] of this.boxes) {
      const a = this.annotations.get(id)
      const img = pages.get(a.locator.page)
      const r = img?.getBoundingClientRect()
      if (!r || r.bottom < host.top || r.top > host.bottom) {
        el.hidden = true
        continue
      }
      const [x, y, w, h] = a.locator.rect
      el.hidden = false
      el.style.left = `${r.left - host.left + x * r.width}px`
      el.style.top = `${r.top - host.top + y * r.height}px`
      el.style.width = `${w * r.width}px`
      el.style.height = `${h * r.height}px`
    }
  },

  // ── marking ───────────────────────────────────────────────────────────

  // The page image under a point, from those showing.
  pageAt(x, y) {
    for (const [page, img] of this.pages()) {
      const r = img.getBoundingClientRect()
      if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return {page, rect: r}
    }
    return null
  },

  down(e) {
    if (!this.marking() || e.target.closest(".annot-bar")) return
    e.preventDefault()
    this.bar.hide()
    const at = this.pageAt(e.clientX, e.clientY)
    this.drag = {x: e.clientX, y: e.clientY, at}
    this.el.setPointerCapture?.(e.pointerId)
  },

  move(e) {
    const d = this.drag
    if (!d?.at) return
    const r = this.clampTo(d.at.rect, d.x, d.y, e.clientX, e.clientY)
    const host = this.el.getBoundingClientRect()
    Object.assign(this.draft.style, {
      left: `${r.left - host.left}px`,
      top: `${r.top - host.top}px`,
      width: `${r.width}px`,
      height: `${r.height}px`,
    })
    this.draft.hidden = r.width < MIN_DRAG && r.height < MIN_DRAG
  },

  up(e) {
    const d = this.drag
    this.drag = null
    if (!d) return
    const moved = Math.hypot(e.clientX - d.x, e.clientY - d.y) >= MIN_DRAG
    if (!moved) {
      this.draft.hidden = true
      return this.tapped(e.clientX, e.clientY)
    }
    if (!d.at) return
    const r = this.clampTo(d.at.rect, d.x, d.y, e.clientX, e.clientY)
    if (r.width < MIN_DRAG || r.height < MIN_DRAG) {
      this.draft.hidden = true
      return
    }
    const p = d.at.rect
    this.pending = {
      page: d.at.page,
      rect: [(r.left - p.left) / p.width, (r.top - p.top) / p.height, r.width / p.width, r.height / p.height],
    }
    this.bar.show(this.boxOf(r), {mode: "new", copy: false})
  },

  // A tap on a region in mark mode: its bar.
  tapped(x, y) {
    const hit = [...this.boxes].reverse().find(([, el]) => {
      if (el.hidden) return false
      const r = el.getBoundingClientRect()
      return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom
    })
    if (!hit) return
    const [id, el] = hit
    this.bar.show(this.boxOf(el.getBoundingClientRect()), {
      mode: "existing",
      annotation: id,
      color: this.annotations.get(id)?.color,
      copy: false,
    })
  },

  // The box between two points, kept inside the page.
  clampTo(page, x1, y1, x2, y2) {
    const cx = (v) => Math.max(page.left, Math.min(v, page.right))
    const cy = (v) => Math.max(page.top, Math.min(v, page.bottom))
    const left = Math.min(cx(x1), cx(x2))
    const top = Math.min(cy(y1), cy(y2))
    return {left, top, width: Math.max(cx(x1), cx(x2)) - left, height: Math.max(cy(y1), cy(y2)) - top}
  },

  boxOf(r) {
    const host = this.el.getBoundingClientRect()
    return {left: r.left - host.left, top: r.top - host.top, width: r.width, height: r.height}
  },

  barAction(action, color) {
    if (this.bar.mode === "existing") {
      const id = this.bar.annotation
      if (action === "color") this.pushEvent("annotation_color", {id, color})
      else if (action === "note") this.pushEvent("annotation_edit", {id})
      else if (action === "delete") this.pushEvent("annotation_delete", {id})
    } else if (this.pending) {
      this.pushEvent("annotate", {
        kind: "highlight",
        color: color || "yellow",
        page: this.pending.page,
        rect: this.pending.rect,
        edit: action === "note",
      })
    }
    this.pending = null
    this.draft.hidden = true
    this.bar.hide()
  },
}

export default ImageAnnotations
