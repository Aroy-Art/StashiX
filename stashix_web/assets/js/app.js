// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import "../vendor/blurhash"
import SaladUI from "./ui/index.js";
import { SaladUIHook } from "./ui/core/hook.js";
import "./ui/components/accordion.js";
import "./ui/components/collapsible.js";
import "./ui/components/command.js";
import "./ui/components/dialog.js";
import "./ui/components/dropdown_menu.js";
import "./ui/components/hover-card.js";
import "./ui/components/popover.js";
import "./ui/components/radio_group.js";
import "./ui/components/select.js";
import "./ui/components/slider.js";
import "./ui/components/switch.js";
import "./ui/components/tabs.js";
import "./ui/components/toast.js";
import "./ui/components/toast-flash.js";
import "./ui/components/tooltip.js";

let Hooks = { SaladUI: SaladUIHook }

Hooks.PublisherSearch = {
  mounted() {
    this.publishers = JSON.parse(this.el.dataset.publishers || "[]")
    this.selectedIds = new Set(JSON.parse(this.el.dataset.selectedIds || "[]"))
    this.inputName = this.el.dataset.inputName
    this.dropdownEl = null
    this.badgesEl = this.el.querySelector(".pub-badges")
    this.input = this.el.querySelector("input[type=text]")

    this.renderBadges()
    this.syncHiddenInputs()

    this.input.addEventListener("input", () => {
      const q = this.input.value.trim()
      if (q === "") { this.closeDropdown(); return }
      this.renderDropdown(q)
    })
    this.input.addEventListener("focus", () => {
      if (this.input.value.trim()) this.renderDropdown(this.input.value.trim())
    })
    this.input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault()
        const first = this.dropdownEl && this.dropdownEl.querySelector("button[data-pub-id]")
        if (first) first.click()
      } else if (e.key === "Escape") {
        this.closeDropdown()
      }
    })
    this.closeOutside = (e) => {
      if (!this.el.contains(e.target)) this.closeDropdown()
    }
    document.addEventListener("click", this.closeOutside)
  },

  updated() {
    // LiveView may patch data attributes — restore input value but keep local state
    const val = this.input.value
    if (this.input.value !== val) this.input.value = val
  },

  destroyed() {
    document.removeEventListener("click", this.closeOutside)
    this.closeDropdown()
  },

  selectPublisher(id) {
    this.selectedIds.add(id)
    this.input.value = ""
    this.closeDropdown()
    this.renderBadges()
    this.syncHiddenInputs()
  },

  removePublisher(id) {
    this.selectedIds.delete(id)
    this.renderBadges()
    this.syncHiddenInputs()
    const q = this.input.value.trim()
    if (q) this.renderDropdown(q)
  },

  renderBadges() {
    if (!this.badgesEl) return
    const pub = (id) => this.publishers.find(p => p.id === id)
    this.badgesEl.innerHTML = [...this.selectedIds].map(id => {
      const p = pub(id)
      if (!p) return ""
      return `<span class="inline-flex items-center gap-1 pl-2 pr-1 py-0.5 rounded-full bg-violet-900/50 border border-violet-700/50 text-violet-300 text-xs">
        ${p.name}
        <button type="button" data-remove-id="${id}" class="flex items-center justify-center w-3.5 h-3.5 rounded-full hover:bg-violet-700 text-violet-400 hover:text-white transition-colors ml-0.5">
          <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
        </button>
      </span>`
    }).join("")
    this.badgesEl.querySelectorAll("button[data-remove-id]").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.stopPropagation()
        this.removePublisher(btn.dataset.removeId)
      })
    })
    this.badgesEl.hidden = this.selectedIds.size === 0
  },

  syncHiddenInputs() {
    this.el.querySelectorAll("input[type=hidden]").forEach(el => el.remove())
    // Always emit at least one empty value so the key is present in form params
    const ids = this.selectedIds.size > 0 ? [...this.selectedIds] : [""]
    ids.forEach(val => {
      const inp = document.createElement("input")
      inp.type = "hidden"
      inp.name = this.inputName
      inp.value = val
      this.el.appendChild(inp)
    })
  },

  renderDropdown(q) {
    const lower = q.toLowerCase()
    const results = this.publishers
      .filter(p => !this.selectedIds.has(p.id) && p.name.toLowerCase().includes(lower))
      .slice(0, 8)

    if (!this.dropdownEl) {
      this.dropdownEl = document.createElement("div")
      this.dropdownEl.className =
        "absolute z-30 top-full left-0 right-0 mt-1 bg-gray-800 border border-gray-700 rounded-lg overflow-hidden shadow-xl"
      this.el.appendChild(this.dropdownEl)
    }

    if (results.length === 0) {
      this.dropdownEl.innerHTML =
        `<div class="px-3 py-2.5 text-sm text-gray-500">No publishers found</div>`
    } else {
      this.dropdownEl.innerHTML = results.map((p, i) =>
        `<button type="button" data-pub-id="${p.id}" class="w-full text-left px-3 py-2 text-sm transition-colors ${i === 0 ? "bg-gray-700/60 text-white hover:bg-gray-700" : "text-gray-300 hover:bg-gray-700 hover:text-white"}">${p.name}</button>`
      ).join("")
      this.dropdownEl.querySelectorAll("button[data-pub-id]").forEach(btn => {
        btn.addEventListener("mousedown", (e) => e.preventDefault())
        btn.addEventListener("click", (e) => {
          e.stopPropagation()
          this.selectPublisher(btn.dataset.pubId)
        })
      })
    }
  },

  closeDropdown() {
    if (this.dropdownEl) { this.dropdownEl.remove(); this.dropdownEl = null }
  }
}

Hooks.SearchNav = {
  mounted() {
    this.activeIndex = -1

    this.onKeydown = (e) => {
      const items = Array.from(this.el.parentElement?.querySelectorAll('a[data-result]') ?? [])

      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        if (items.length === 0) return
        e.preventDefault()
        const next = e.key === 'ArrowDown'
          ? Math.min(this.activeIndex + 1, items.length - 1)
          : Math.max(this.activeIndex - 1, -1)
        this.setActive(next, items)
      } else if (e.key === 'Enter' && this.activeIndex >= 0 && items[this.activeIndex]) {
        e.preventDefault()
        window.location.href = items[this.activeIndex].href
      } else if (e.key === 'Escape') {
        this.activeIndex = -1
        this.el.blur()
      } else {
        this.activeIndex = -1
        items.forEach(el => this.clearActive(el))
      }
    }

    this.onGlobalKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault()
        if (document.activeElement === this.el) {
          this.el.blur()
        } else {
          this.el.focus()
          this.el.select()
        }
      }
    }

    this.el.addEventListener('keydown', this.onKeydown)
    window.addEventListener('keydown', this.onGlobalKeydown)
  },

  destroyed() {
    this.el.removeEventListener('keydown', this.onKeydown)
    window.removeEventListener('keydown', this.onGlobalKeydown)
  },

  setActive(idx, items) {
    items.forEach((el, i) => {
      if (i === idx) {
        el.style.backgroundColor = 'rgb(31 41 55)'
        el.style.color = '#fff'
      } else {
        this.clearActive(el)
      }
    })
    this.activeIndex = idx
    if (idx >= 0 && items[idx]) items[idx].scrollIntoView({ block: 'nearest' })
  },

  clearActive(el) {
    el.style.backgroundColor = ''
    el.style.color = ''
  }
}

Hooks.CoverImage = {
  mounted() {
    const hash = this.el.dataset.blurhash
    const canvasId = this.el.dataset.canvasId
    this.canvas = canvasId ? document.getElementById(canvasId) : null

    if (hash && this.canvas) {
      try { window.decodeBlurhash(hash, this.canvas) } catch (_) {}
    }

    this.el.style.opacity = '0'
    this.el.style.transition = 'opacity 0.3s ease'

    const reveal = () => {
      this.el.style.opacity = '1'
      if (this.canvas) {
        this.canvas.style.transition = 'opacity 0.3s ease'
        this.canvas.style.opacity = '0'
        const c = this.canvas
        setTimeout(() => { if (c.parentNode) c.parentNode.removeChild(c) }, 350)
        this.canvas = null
      }
    }

    if (this.el.complete && this.el.naturalWidth > 0) {
      reveal()
    } else {
      this.el.addEventListener('load', reveal, { once: true })
      this.el.addEventListener('error', () => {
        this.el.style.opacity = '1'
        if (this.canvas) this.canvas.style.opacity = '0'
      }, { once: true })
    }
  },

  destroyed() {
    if (this.canvas && this.canvas.parentNode) {
      this.canvas.parentNode.removeChild(this.canvas)
    }
  }
}

Hooks.PageImage = {
  mounted() {
    this.spinner = this.el.previousElementSibling
    this.el.addEventListener('load', () => this.reveal())
    this.el.addEventListener('error', () => this.reveal())
    if (this.el.complete && this.el.naturalWidth > 0) {
      this.reveal()
    } else {
      this.hide()
    }
  },
  updated() {
    this.hide()
    if (this.el.complete && this.el.naturalWidth > 0) this.reveal()
  },
  hide() {
    this.el.style.opacity = '0'
    if (this.spinner) this.spinner.style.display = 'flex'
  },
  reveal() {
    this.el.style.opacity = '1'
    if (this.spinner) this.spinner.style.display = 'none'
  }
}

Hooks.PageSlider = {
  mounted() {
    this.isDragging = false
    this.el.addEventListener('pointerdown', () => { this.isDragging = true })
    this.el.addEventListener('change', (e) => {
      this.isDragging = false
      this.pushEvent("goto_page", {page: e.target.value})
    })
    // Safety net: clear flag if pointer leaves without firing change
    this.el.addEventListener('pointercancel', () => { this.isDragging = false })
  },
  updated() {
    // Only sync server value when user isn't dragging
    if (!this.isDragging) {
      this.el.value = this.el.getAttribute('value')
    }
  }
}

Hooks.ReaderKeyboard = {
  mounted() {
    this.handleKey = (e) => {
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return
      if (e.key === "ArrowRight" || e.key === "ArrowDown" || e.key === " ") {
        e.preventDefault()
        this.pushEvent("next_page", {})
      } else if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
        e.preventDefault()
        this.pushEvent("prev_page", {})
      } else if (e.key === "+" || e.key === "=") {
        e.preventDefault()
        window.dispatchEvent(new CustomEvent("reader:zoom-in"))
      } else if (e.key === "-") {
        e.preventDefault()
        window.dispatchEvent(new CustomEvent("reader:zoom-out"))
      } else if (e.key === "0") {
        window.dispatchEvent(new CustomEvent("reader:zoom-reset"))
      }
    }
    window.addEventListener("keydown", this.handleKey)
  },
  destroyed() {
    window.removeEventListener("keydown", this.handleKey)
  }
}

// Reader zoom / pan / navigation.
//
// Everything the reading area does with a pointer is handled here, on the
// Pointer Events API alone. The zones carry `data-action` instead of
// `phx-click` so LiveView never sees these interactions -- the hook decides
// whether a gesture was a tap (navigate / toggle overlay), a double tap
// (zoom), a drag (pan) or a pinch, and pushes the event itself. One code path,
// no synthetic mouse events to second-guess.
const TAP_MS = 260      // how long the overlay toggle waits for a second tap
const DBLTAP_MS = 500   // two taps this far apart still count as a double tap
const TAP_SLOP = 10     // px of movement still counted as a tap
const DBLTAP_SLOP = 40  // px between two taps for them to count as a double tap
const MIN_ZOOM = 1
const MAX_ZOOM = 5
const ZOOMED = 1.01     // above this we consider the view zoomed in
const ZONE_SIDE = 22        // % width of each nav zone; the rest is the centre
const ZONE_SIDE_ZOOMED = 12 // nav zones give way to panning once zoomed in

Hooks.ReaderZoom = {
  mounted() {
    // Set `window.READER_DEBUG = true` in the console to trace gestures.
    this.debug = (...a) => { if (window.READER_DEBUG) console.log("[zoom]", ...a) }
    // A second hook on the same element would fight this one over the
    // transform. That should be impossible, but it happened once already
    // (duplicate app.js from a nested document), so make it loud.
    if (this.el.__readerZoom) {
      console.warn("ReaderZoom mounted twice on the same element -- zoom will fight itself")
    }
    this.el.__readerZoom = this

    this.zoom = 1
    this.panX = 0
    this.panY = 0
    this.pointers = new Map()   // pointerId -> {x, y}
    this.gesture = null         // "pan" | "pinch" | null
    this.pinch = null
    this.tapTimer = null
    this.pendingAction = null
    this.lastTapAt = 0
    this.lastTapX = 0
    this.lastTapY = 0
    this.lastPageSrc = this.currentPageSrc()

    this.buildIndicator()

    this.onPointerDown  = (e) => this.pointerDown(e)
    this.onPointerMove  = (e) => this.pointerMove(e)
    this.onPointerUp    = (e) => this.pointerUp(e)
    this.onWheel        = (e) => this.wheel(e)
    this.onGesture      = (e) => e.preventDefault()  // Safari native pinch
    this.onZoomIn       = () => this.zoomBy(1.25)
    this.onZoomOut      = () => this.zoomBy(1 / 1.25)
    this.onZoomReset    = () => this.setZoom(1)

    this.el.addEventListener("pointerdown",   this.onPointerDown)
    this.el.addEventListener("pointermove",   this.onPointerMove)
    this.el.addEventListener("pointerup",     this.onPointerUp)
    this.el.addEventListener("pointercancel", this.onPointerUp)
    this.el.addEventListener("wheel",         this.onWheel,   {passive: false})
    this.el.addEventListener("gesturestart",  this.onGesture, {passive: false})
    this.el.addEventListener("gesturechange", this.onGesture, {passive: false})
    this.el.addEventListener("gestureend",    this.onGesture, {passive: false})
    window.addEventListener("reader:zoom-in",    this.onZoomIn)
    window.addEventListener("reader:zoom-out",   this.onZoomOut)
    window.addEventListener("reader:zoom-reset", this.onZoomReset)

    this.render()
  },

  // LiveView morphdoms the whole reader on every patch, which strips the
  // inline styles we set. This runs after the patch, so re-assert them.
  updated() {
    const src = this.currentPageSrc()
    this.debug("updated", {zoom: this.zoom, pageChanged: !!src && src !== this.lastPageSrc})
    if (src && src !== this.lastPageSrc) {
      this.lastPageSrc = src
      this.zoom = 1
      this.panX = 0
      this.panY = 0
    }
    if (!this.indicator.isConnected) document.body.appendChild(this.indicator)
    this.render()
  },

  destroyed() {
    this.clearTap()
    this.el.removeEventListener("pointerdown",   this.onPointerDown)
    this.el.removeEventListener("pointermove",   this.onPointerMove)
    this.el.removeEventListener("pointerup",     this.onPointerUp)
    this.el.removeEventListener("pointercancel", this.onPointerUp)
    this.el.removeEventListener("wheel",         this.onWheel)
    this.el.removeEventListener("gesturestart",  this.onGesture)
    this.el.removeEventListener("gesturechange", this.onGesture)
    this.el.removeEventListener("gestureend",    this.onGesture)
    window.removeEventListener("reader:zoom-in",    this.onZoomIn)
    window.removeEventListener("reader:zoom-out",   this.onZoomOut)
    window.removeEventListener("reader:zoom-reset", this.onZoomReset)
    this.indicator.remove()
    if (this.el.__readerZoom === this) delete this.el.__readerZoom
  },

  // --- gesture handling ----------------------------------------------------

  pointerDown(e) {
    if (e.pointerType === "mouse" && e.button !== 0) return
    // The zoom controls live inside the reading area; capturing their pointer
    // here would swallow their clicks.
    if (e.target.closest("button, a, input, select, textarea")) return
    const zone = e.target.closest(".reader-click-zone")
    this.pointers.set(e.pointerId, {x: e.clientX, y: e.clientY})
    try { this.el.setPointerCapture(e.pointerId) } catch (_) {}

    if (this.pointers.size === 1) {
      this.start = {
        x: e.clientX, y: e.clientY,
        panX: this.panX, panY: this.panY,
        action: zone && zone.dataset.action,
        moved: false
      }
      this.gesture = null
    } else if (this.pointers.size === 2) {
      // A second finger cancels any tap in flight and starts a pinch.
      this.clearTap()
      if (this.start) this.start.moved = true
      this.gesture = "pinch"
      this.pinch = {dist: this.spread(), zoom: this.zoom}
      this.debug("pinch start", this.pinch)
    }
  },

  pointerMove(e) {
    const p = this.pointers.get(e.pointerId)
    if (!p) return
    p.x = e.clientX
    p.y = e.clientY

    if (this.gesture === "pinch" && this.pointers.size >= 2) {
      e.preventDefault()
      const dist = this.spread()
      if (this.pinch.dist > 0) {
        const mid = this.midpoint()
        this.setZoom(this.pinch.zoom * (dist / this.pinch.dist), mid.x, mid.y)
      }
      return
    }
    if (this.pointers.size !== 1 || !this.start) return

    const dx = e.clientX - this.start.x
    const dy = e.clientY - this.start.y
    if (!this.start.moved && Math.hypot(dx, dy) > TAP_SLOP) {
      this.start.moved = true
      // Only drag-to-pan when there is something to pan.
      if (this.zoom > ZOOMED) this.gesture = "pan"
    }
    if (this.gesture === "pan") {
      e.preventDefault()
      this.panX = this.start.panX + dx / this.zoom
      this.panY = this.start.panY + dy / this.zoom
      this.render()
    }
  },

  pointerUp(e) {
    if (!this.pointers.has(e.pointerId)) return
    this.pointers.delete(e.pointerId)
    try { this.el.releasePointerCapture(e.pointerId) } catch (_) {}

    if (this.pointers.size < 2 && this.gesture === "pinch") {
      this.pinch = null
      this.gesture = null
      // Remaining finger must not turn into a tap or a pan jump.
      this.pointers.clear()
      this.start = null
      return
    }
    if (this.pointers.size > 0) return

    const start = this.start
    this.start = null
    this.gesture = null
    if (!start || start.moved || e.type === "pointercancel") return
    this.tap(e.clientX, e.clientY, start.action)
  },

  tap(x, y, action) {
    const now = Date.now()
    const near = Math.abs(x - this.lastTapX) < DBLTAP_SLOP &&
                 Math.abs(y - this.lastTapY) < DBLTAP_SLOP
    // Deliberately independent of the TAP_MS timer: system double-click speed
    // is commonly ~500ms, so the second tap regularly lands after the first
    // has already fired. Falling back to "single tap" there is what made
    // double tap look dead.
    const isSecond = near && this.lastTapAt > 0 && now - this.lastTapAt < DBLTAP_MS

    if (isSecond) {
      const stillPending = this.tapTimer !== null
      this.clearTap()
      this.lastTapAt = 0
      // If the first tap's action already went out, undo it. Only the overlay
      // toggle is ever deferred, and it is its own inverse.
      if (!stillPending && this.pendingAction) this.pushEvent(this.pendingAction, {})
      this.pendingAction = null
      this.debug("double tap -> zoom toggle", {x, y, zoom: this.zoom, stillPending})
      this.toggleZoom(x, y)
      return
    }

    this.lastTapAt = now
    this.lastTapX = x
    this.lastTapY = y

    // Page turns fire on the spot -- waiting on them to see whether a second
    // tap is coming makes the reader feel sluggish. Only the overlay toggle
    // (and taps that hit no zone at all) are held back, so double tap to zoom
    // lives in the centre zone, which covers most of the screen and widens
    // further once zoomed in.
    if (action && action !== "toggle_overlay") {
      this.clearTap()
      this.pendingAction = null
      this.lastTapAt = 0
      this.debug("tap -> nav", {x, y, action})
      this.pushEvent(action, {})
      return
    }

    this.debug("tap", {x, y, action})
    this.clearTap()
    this.pendingAction = action || null
    this.tapTimer = setTimeout(() => {
      this.tapTimer = null
      if (this.pendingAction) this.pushEvent(this.pendingAction, {})
    }, TAP_MS)
  },

  clearTap() {
    if (this.tapTimer !== null) {
      clearTimeout(this.tapTimer)
      this.tapTimer = null
    }
  },

  wheel(e) {
    if (!e.ctrlKey && !e.metaKey) return
    e.preventDefault()
    this.setZoom(this.zoom * (e.deltaY < 0 ? 1.15 : 1 / 1.15), e.clientX, e.clientY)
  },

  spread() {
    const [a, b] = [...this.pointers.values()]
    return Math.hypot(a.x - b.x, a.y - b.y)
  },

  midpoint() {
    const [a, b] = [...this.pointers.values()]
    return {x: (a.x + b.x) / 2, y: (a.y + b.y) / 2}
  },

  // --- zoom ----------------------------------------------------------------

  zoomBy(factor) {
    const r = this.el.getBoundingClientRect()
    this.setZoom(this.zoom * factor, r.left + r.width / 2, r.top + r.height / 2)
  },

  // Zoom about a viewport point, keeping the content under it in place.
  // Transform is `scale(z) translate(p)` about the element centre, so a
  // content point c sits at screen offset s = z * (c + p); holding c fixed
  // across a zoom change gives p' = p + s * (1/z' - 1/z).
  setZoom(next, clientX, clientY) {
    const z = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, next))
    if (z !== this.zoom) {
      const r = this.el.getBoundingClientRect()
      const sx = (clientX === undefined ? r.left + r.width / 2 : clientX) - (r.left + r.width / 2)
      const sy = (clientY === undefined ? r.top + r.height / 2 : clientY) - (r.top + r.height / 2)
      const f = 1 / z - 1 / this.zoom
      this.panX += sx * f
      this.panY += sy * f
      this.zoom = z
    }
    if (this.zoom <= MIN_ZOOM + 0.001) {
      this.zoom = MIN_ZOOM
      this.panX = 0
      this.panY = 0
    }
    this.render()
  },

  toggleZoom(clientX, clientY) {
    if (this.zoom > ZOOMED) {
      this.setZoom(1)
      return
    }
    const img = this.pagesEl() && this.pagesEl().querySelector("img")
    if (!img || !img.naturalWidth) return
    // Width the image occupies at zoom 1 -> the factor that shows it 1:1.
    const shown = img.getBoundingClientRect().width / this.zoom
    if (!shown) return
    this.setZoom(Math.max(1.5, img.naturalWidth / shown), clientX, clientY)
  },

  // --- rendering -----------------------------------------------------------

  pagesEl() {
    return document.getElementById("reader-pages")
  },

  currentPageSrc() {
    const img = this.pagesEl() && this.pagesEl().querySelector("img")
    return img && img.src
  },

  render() {
    this.clampPan()
    const pages = this.pagesEl()
    if (pages) {
      pages.style.transform =
        `scale(${this.zoom}) translate(${this.panX}px, ${this.panY}px)`
    }

    const zoomed = this.zoom > ZOOMED
    // Shrink the nav zones when zoomed so most of the area is free to pan.
    const side = zoomed ? ZONE_SIDE_ZOOMED : ZONE_SIDE
    const left = this.el.querySelector(".reader-zone-left")
    const right = this.el.querySelector(".reader-zone-right")
    const center = this.el.querySelector(".reader-zone-center")
    if (left) left.style.width = `${side}%`
    if (right) right.style.width = `${side}%`
    if (center) {
      center.style.left = `${side}%`
      center.style.width = `${100 - 2 * side}%`
    }
    this.el.style.cursor = zoomed ? "grab" : ""

    if (zoomed) {
      this.indicator.textContent = `${Math.round(this.zoom * 100)}%`
      this.indicator.style.display = "block"
    } else {
      this.indicator.style.display = "none"
    }
  },

  clampPan() {
    if (this.zoom <= MIN_ZOOM) {
      this.panX = 0
      this.panY = 0
      return
    }
    const r = this.el.getBoundingClientRect()
    const maxX = r.width * (this.zoom - 1) / (2 * this.zoom)
    const maxY = r.height * (this.zoom - 1) / (2 * this.zoom)
    this.panX = Math.max(-maxX, Math.min(maxX, this.panX))
    this.panY = Math.max(-maxY, Math.min(maxY, this.panY))
  },

  buildIndicator() {
    this.indicator = document.createElement("div")
    this.indicator.style.cssText = [
      "position:fixed", "bottom:56px", "right:16px", "z-index:50",
      "background:rgba(0,0,0,0.75)", "color:#fff", "padding:3px 8px",
      "border-radius:6px", "font-size:12px", "font-family:monospace",
      "pointer-events:auto", "display:none", "cursor:pointer",
      "user-select:none", "border:1px solid rgba(255,255,255,0.15)"
    ].join(";")
    this.indicator.title = "Click to reset zoom (0)"
    this.indicator.addEventListener("click", () => this.setZoom(1))
    document.body.appendChild(this.indicator)
  }
}

if ("serviceWorker" in navigator) {
  const noCache = document.querySelector('meta[name="sw-no-cache"]')?.content === "true"
  const swUrl = "/sw.js" + (noCache ? "?nocache=1" : "")
  window.addEventListener("load", async () => {
    const regs = await navigator.serviceWorker.getRegistrations()
    for (const reg of regs) {
      const url = reg.active?.scriptURL || reg.installing?.scriptURL || reg.waiting?.scriptURL || ""
      if (noCache !== url.includes("nocache=1")) await reg.unregister()
    }
    navigator.serviceWorker.register(swUrl)
  })
}

// A second copy of this bundle on the page would stand up a second LiveSocket,
// which fails with "Cannot bind multiple views to the same DOM element" and
// leaves every hook mounted twice -- two ReaderZoom instances fighting over the
// same transform. Refuse to boot twice, and say so loudly: the duplicate
// <script> tag is the thing that needs fixing.
if (window.__stashixBooted) {
  console.error(
    "app.js was evaluated twice -- skipping the second LiveSocket. " +
    "Check the page source for a duplicate <script src=\"/assets/app.js\"> " +
    "(usually a LiveView template rendering its own <html>/<head> inside the root layout)."
  )
} else {
  window.__stashixBooted = true

  let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
  let liveSocket = new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
    hooks: Hooks
  })

  // Show progress bar on live navigation and form submits
  topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
  window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
  window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

  window.addEventListener("stashix:scroll-to", (e) => {
    const el = document.getElementById(e.detail.id)
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" })
  })

  // connect if there are any LiveViews on the page
  liveSocket.connect()

  // expose liveSocket on window for web console debug logs and latency simulation:
  // >> liveSocket.enableDebug()
  // >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
  // >> liveSocket.disableLatencySim()
  window.liveSocket = liveSocket
}
