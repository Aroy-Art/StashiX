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
import * as echarts from "../vendor/echarts.min"
import InkMenu from "./hooks/ink_menu.js"
import InkDialog from "./hooks/ink_dialog.js"
import Shelf from "./hooks/shelf.js"

let Hooks = { InkMenu, InkDialog, Shelf }

Hooks.Sidebar = {
  mounted() {
    this.isOpen = false
    window.toggleSidebar = () => {
      this.isOpen = !this.isOpen
      this.apply()
    }
    window.closeSidebar = () => {
      this.isOpen = false
      this.apply()
    }
  },
  updated() {
    this.apply()
  },
  apply() {
    const backdrop = document.getElementById('sidebar-backdrop')
    if (this.isOpen) {
      this.el.classList.remove('-translate-x-full')
      if (backdrop) backdrop.classList.remove('hidden')
    } else {
      this.el.classList.add('-translate-x-full')
      if (backdrop) backdrop.classList.add('hidden')
    }
  }
}

const echartsLib = echarts.init ? echarts : echarts.default

// Chart chrome in the display face; series colours come with each option.
const chartFont = { fontFamily: '"Big Shoulders Display", "Arial Narrow", sans-serif', fontWeight: 600, fontSize: 13 }
echartsLib.registerTheme("ink", {
  textStyle: { fontFamily: "ui-sans-serif, system-ui, sans-serif" },
  categoryAxis: { axisLabel: chartFont, axisLine: { lineStyle: { color: "rgba(255,255,255,0.2)" } } },
  valueAxis: { axisLabel: chartFont },
  legend: { textStyle: { ...chartFont, color: "#d1d5db" } },
  tooltip: {
    backgroundColor: "#09090b",
    borderColor: "rgba(255,255,255,0.15)",
    textStyle: { color: "#f3f4f6" },
    extraCssText: "box-shadow: 4px 4px 0 0 #4fe8eb; border-radius: 6px;",
  },
})

Hooks.Chart = {
  mounted() {
    requestAnimationFrame(() => {
      const chart = echartsLib.init(this.el, "ink", {renderer: "canvas"})
      this.chart = chart

      const ro = new ResizeObserver(() => chart.resize())
      ro.observe(this.el)
      this.ro = ro

      try {
        const option = JSON.parse(this.el.dataset.option || "{}")
        if (Object.keys(option).length > 0) chart.setOption(option)
      } catch (_) {}

      chart.on("click", (params) => {
        const link = params.data?.link
        if (link) window.liveSocket.pushHistoryState ? window.liveSocket.navigate(link) : (window.location.href = link)
      })
    })
  },

  destroyed() {
    if (this.ro) this.ro.disconnect()
    if (this.chart) this.chart.dispose()
  }
}

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

// Reads the current publisher selection from a PublisherSearch picker and pushes
// the IDs to the server so unsaved changes are included in the push preview/action.
Hooks.PushPublishers = {
  mounted() {
    this.el.addEventListener("click", () => {
      const picker = document.getElementById(this.el.dataset.pickerId)
      const ids = picker
        ? [...picker.querySelectorAll("input[type=hidden]")].map(el => el.value).filter(Boolean)
        : []
      this.pushEvent("open_push_publishers_dialog", { publisher_ids: ids })
    })
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
        // A page can claim the shortcut for its own search box (e.g. /search)
        const target = document.querySelector('[data-ctrl-k-target]') || this.el
        if (document.activeElement === target) {
          target.blur()
        } else {
          target.focus()
          target.select()
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

// Keyboard navigation + click-outside for the server-rendered creator picker
// on the search page. Options are buttons marked [data-option].
Hooks.CreatorCombobox = {
  mounted() {
    this.activeIndex = -1
    this.input = this.el.querySelector("input[type=text]")

    this.onKeydown = (e) => {
      const options = this.options()

      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        if (options.length === 0) return
        e.preventDefault()
        const next = e.key === "ArrowDown"
          ? Math.min(this.activeIndex + 1, options.length - 1)
          : Math.max(this.activeIndex - 1, 0)
        this.setActive(next)
      } else if (e.key === "Enter") {
        // never submit the surrounding filter form from here
        e.preventDefault()
        const target = options[this.activeIndex] || options[0]
        if (target) target.click()
      } else if (e.key === "Escape") {
        this.close()
      }
    }

    this.onClickOutside = (e) => {
      if (!this.el.contains(e.target) && this.isOpen()) this.close()
    }

    // After picking, clear the box and keep focus so the next creator can be
    // typed straight away (LiveView won't overwrite a focused input's value).
    this.onPick = (e) => {
      if (!e.target.closest("[data-option]")) return
      this.activeIndex = -1
      this.input.value = ""
      this.input.focus()
    }

    this.input.addEventListener("keydown", this.onKeydown)
    this.el.addEventListener("click", this.onPick)
    document.addEventListener("click", this.onClickOutside)
  },

  updated() {
    // suggestions were re-rendered; restore highlight if still in range
    this.input = this.el.querySelector("input[type=text]")
    this.input.removeEventListener("keydown", this.onKeydown)
    this.input.addEventListener("keydown", this.onKeydown)
    const options = this.options()
    this.setActive(this.activeIndex < options.length ? this.activeIndex : -1)
  },

  destroyed() {
    document.removeEventListener("click", this.onClickOutside)
  },

  options() {
    return Array.from(this.el.querySelectorAll("[data-option]"))
  },

  isOpen() {
    return this.el.querySelector("[role=listbox]") !== null
  },

  close() {
    this.activeIndex = -1
    this.input.value = ""
    this.pushEvent("close_creator_suggestions", {})
  },

  setActive(idx) {
    this.options().forEach((el, i) => {
      if (i === idx) {
        el.setAttribute("data-active", "")
        el.setAttribute("aria-selected", "true")
        el.scrollIntoView({ block: "nearest" })
      } else {
        el.removeAttribute("data-active")
        el.removeAttribute("aria-selected")
      }
    })
    this.activeIndex = idx
  }
}

// Two-handle year slider over the release-year histogram on the search page.
// Handles snap to years that have books; bars/label update live while
// dragging and "set_years" is pushed on release (null = no bound).
Hooks.YearRange = {
  mounted() {
    this.read()

    this.onInput = (e) => {
      const thumb = e.target.dataset.thumb
      if (!thumb) return
      // keep the surrounding filter form from treating this as a change
      e.stopPropagation()
      let v = this.snap(+e.target.value)
      if (thumb === "lo") v = Math.min(v, +this.hi.value)
      else v = Math.max(v, +this.lo.value)
      e.target.value = v
      this.render()
    }

    this.onChange = (e) => {
      if (!e.target.dataset.thumb) return
      e.stopPropagation()
      const lo = +this.lo.value, hi = +this.hi.value
      if (lo === this.from && hi === this.to) return
      this.from = lo
      this.to = hi
      this.pushEvent("set_years", {
        from: lo === this.min ? null : String(lo),
        to: hi === this.max ? null : String(hi)
      })
    }

    this.el.addEventListener("input", this.onInput)
    this.el.addEventListener("change", this.onChange)
  },

  updated() {
    this.read()
  },

  read() {
    this.years = JSON.parse(this.el.dataset.years)
    this.counts = JSON.parse(this.el.dataset.counts)
    this.min = +this.el.dataset.min
    this.max = +this.el.dataset.max
    this.lo = this.el.querySelector("[data-thumb=lo]")
    this.hi = this.el.querySelector("[data-thumb=hi]")
    this.from = +this.lo.value
    this.to = +this.hi.value
    this.render()
  },

  // nearest year that actually has books
  snap(v) {
    return this.years.reduce((best, y) => Math.abs(y - v) < Math.abs(best - v) ? y : best)
  },

  render() {
    const lo = +this.lo.value, hi = +this.hi.value
    const span = Math.max(this.max - this.min, 1)
    let total = 0

    this.el.querySelectorAll("[data-bar]").forEach(bar => {
      const y = +bar.dataset.year
      const active = y >= lo && y <= hi && this.counts[y]
      bar.toggleAttribute("data-active", !!active)
      if (active) total += this.counts[y]
    })

    const track = this.el.querySelector("[data-track]")
    track.style.left = `${(lo - this.min) / span * 100}%`
    track.style.right = `${(this.max - hi) / span * 100}%`

    this.el.querySelector("[data-label]").textContent =
      lo === this.min && hi === this.max ? "Any year" : `${lo} – ${hi}`
    this.el.querySelector("[data-total]").textContent = `${total} books`

    // when both handles sit at the top end, keep the low one grabbable
    this.lo.style.zIndex = lo > this.min + span / 2 ? 3 : 1
    this.hi.style.zIndex = 2
  }
}

// Cross-fades the blurred cover wash behind a page header when its source
// changes (the search page swaps it to the top hit as results change). The
// element is phx-update="ignore"; only data-src is patched by the server.
Hooks.BackdropFade = {
  mounted() {
    this.show(this.el.dataset.src)
  },

  updated() {
    if ((this.el.dataset.src || "") !== this.src) this.show(this.el.dataset.src)
  },

  show(src) {
    this.src = src || ""
    const old = Array.from(this.el.children)
    const fadeOut = () => old.forEach(img => {
      img.classList.add("is-hidden")
      setTimeout(() => img.remove(), 650)
    })
    if (!src) return fadeOut()

    const img = new Image()
    img.alt = ""
    img.className = "backdrop-layer is-hidden w-full h-full object-cover"
    img.onload = () => {
      // a newer cover was requested while this one loaded
      if (this.src !== src) return
      requestAnimationFrame(() => img.classList.remove("is-hidden"))
      fadeOut()
    }
    img.onerror = () => {
      img.remove()
      if (this.src === src) fadeOut()
    }
    this.el.appendChild(img)
    img.src = src
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
  // The track fill is a CSS gradient stopping at --fill. The server renders it,
  // but it has to follow the thumb while dragging, before any event is pushed.
  paint() {
    const max = Number(this.el.max) || 0
    const fill = max > 0 ? (Number(this.el.value) / max) * 100 : 100
    this.el.style.setProperty("--fill", `${fill}%`)
  },
  mounted() {
    this.isDragging = false
    this.el.addEventListener('input', () => this.paint())
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
    this.paint()
  }
}

// Path of the page the reader was opened from, i.e. the history entry right
// below it. Leaving the reader for that same page pops back onto it instead of
// stacking a second copy; anything else replaces the reader's entry. Either way
// the reader is gone from the history, so "back" never reopens it.
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

Hooks.ReaderKeyboard = {
  mounted() {
    this.handleEvent("reader:exit", ({to}) => {
      if (pageBelowReader === to) window.history.back()
      else this.js().navigate(to, {replace: true})
    })
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
// whether a gesture was a tap (navigate / toggle overlay), a double tap (fit
// the page to the screen width), a triple tap (actual size), a drag (pan) or a
// pinch, and pushes the event itself. One code path, no synthetic mouse events
// to second-guess.
const TAP_MS = 260      // how long the overlay toggle waits for a second tap
const DBLTAP_MS = 500   // taps this far apart still chain into a double / triple tap
const TAP_SLOP = 10     // px of movement still counted as a tap
const DBLTAP_SLOP = 40  // px between two taps for them to count as a double tap
const MIN_ZOOM = 1
const MAX_ZOOM = 5
const ZOOMED = 1.01     // above this we consider the view zoomed in
const FALLBACK_ZOOM = 2 // double tap when the page already fills the width
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
    this.tapCount = 0
    this.lastPageSrc = this.currentPageSrc()

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
    const chained = near && this.lastTapAt > 0 && now - this.lastTapAt < DBLTAP_MS

    if (chained && this.tapCount === 2) {
      // Third tap: whatever the double tap did, land on actual size.
      this.lastTapAt = 0
      this.tapCount = 0
      this.debug("triple tap -> actual size", {x, y, zoom: this.zoom})
      this.zoomToActualSize(x, y)
      return
    }

    if (chained) {
      const stillPending = this.tapTimer !== null
      this.clearTap()
      // If the first tap's action already went out, undo it. Only the overlay
      // toggle is ever deferred, and it is its own inverse.
      if (!stillPending && this.pendingAction) this.pushEvent(this.pendingAction, {})
      this.pendingAction = null
      // Keep the chain open so a third tap can follow.
      this.lastTapAt = now
      this.lastTapX = x
      this.lastTapY = y
      this.tapCount = 2
      this.debug("double tap -> zoom toggle", {x, y, zoom: this.zoom, stillPending})
      this.toggleZoom(x, y)
      return
    }

    this.lastTapAt = now
    this.lastTapX = x
    this.lastTapY = y
    this.tapCount = 1

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
    // Actual size can sit past MAX_ZOOM for a large scan on a small screen.
    const z = Math.max(MIN_ZOOM, Math.min(Math.max(MAX_ZOOM, this.actualSizeZoom() || 0), next))
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

  // Double tap: in to "page width fills the screen", or back out if zoomed.
  toggleZoom(clientX, clientY) {
    if (this.zoom > ZOOMED) {
      this.setZoom(1)
      return
    }
    const fit = this.fitWidthZoom()
    if (fit && fit > 1.05) {
      // The pages are centred, so zoom about the centre line: the left and
      // right edges land exactly on the screen edges. Vertically, keep the
      // tapped spot in place.
      const r = this.el.getBoundingClientRect()
      this.setZoom(fit, r.left + r.width / 2, clientY)
    } else {
      // Already as wide as the screen (portrait phone, "fit width" mode).
      this.setZoom(FALLBACK_ZOOM, clientX, clientY)
    }
  },

  // Triple tap: one image pixel per CSS pixel -- 100% on the zoom readout.
  zoomToActualSize(clientX, clientY) {
    const actual = this.actualSizeZoom()
    if (actual) this.setZoom(actual, clientX, clientY)
  },

  pageImages() {
    const pages = this.pagesEl()
    return pages ? [...pages.querySelectorAll("img")] : []
  },

  // Zoom factor at which the visible page(s) span the reading area's width.
  fitWidthZoom() {
    const shown = this.pageImages()
      .reduce((sum, img) => sum + img.getBoundingClientRect().width, 0) / this.zoom
    return shown ? this.el.getBoundingClientRect().width / shown : null
  },

  // Zoom factor that shows the page at its natural pixel size.
  actualSizeZoom() {
    const img = this.pageImages()[0]
    if (!img || !img.naturalWidth) return null
    const shown = img.getBoundingClientRect().width / this.zoom
    return shown ? img.naturalWidth / shown : null
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

    // The readout is a cell of the zoom controls, so it slides away with the
    // overlay. It shows the page's real scale: 100% is actual size.
    const level = document.getElementById("reader-zoom-level")
    if (level) {
      const actual = this.actualSizeZoom()
      level.textContent = `${Math.round((actual ? this.zoom / actual : this.zoom) * 100)}%`
      level.style.display = zoomed ? "flex" : "none"
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

// Live navigation swaps the page over the WebSocket, so the target's images only
// start loading once the new page has rendered. Hovering (or touching/focusing)
// a link warms the HTTP cache with them instead. The URLs have to match what the
// target page renders exactly -- see BookLive's hero cover/backdrop and
// ReaderLive's page <img>.
const prefetchedImages = new Set()

function prefetchImagesFor(href) {
  let url
  try { url = new URL(href, window.location.href) } catch (_) { return [] }
  if (url.origin !== window.location.origin) return []

  let m
  if ((m = url.pathname.match(/^\/book\/(\d+)$/))) {
    return [`/api/books/${m[1]}/cover?s=l`, `/api/books/${m[1]}/cover?s=s`]
  }
  if ((m = url.pathname.match(/^\/read\/(\d+)$/))) {
    // Without page=0 the reader resumes at a page only the server knows.
    const format = url.searchParams.get("format")
    if (url.searchParams.get("page") === "0" && format) {
      return [`/api/books/${m[1]}/page/0?format=${encodeURIComponent(format)}`]
    }
  }
  return []
}

function prefetchLink(link) {
  if (navigator.connection?.saveData) return
  for (const src of prefetchImagesFor(link.href)) {
    if (prefetchedImages.has(src)) continue
    prefetchedImages.add(src)
    new Image().src = src
  }
}

function initImagePrefetch() {
  const linkOf = (e) => e.target.closest?.("a[href]")
  let hoverTimer = null

  // Short delay so sweeping the pointer across a grid does not fetch every cover.
  document.addEventListener("mouseover", (e) => {
    const link = linkOf(e)
    if (!link) return
    clearTimeout(hoverTimer)
    hoverTimer = setTimeout(() => prefetchLink(link), 65)
  })
  document.addEventListener("mouseout", (e) => {
    if (linkOf(e)) clearTimeout(hoverTimer)
  })

  const now = (e) => {
    const link = linkOf(e)
    if (link) prefetchLink(link)
  }
  document.addEventListener("touchstart", now, {passive: true})
  document.addEventListener("focusin", now)
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

  // Closing a URL-driven dialog pops the history entry that opened it (see
  // StashixWeb.DialogHistory), so "back" does not reopen it.
  window.addEventListener("phx:history-back", () => window.history.back())

  // Clear a text input client-side and keep the cursor in it. Used alongside a
  // server push, since LiveView won't overwrite the value of a focused input.
  window.addEventListener("stashix:clear-input", (e) => {
    e.target.value = ""
    e.target.focus()
  })

  // Arrow buttons on a shelf: scroll the row by most of its visible width.
  window.addEventListener("stashix:scroll-by", (e) => {
    e.target.scrollBy({ left: e.detail.pages * e.target.clientWidth * 0.8, behavior: "smooth" })
  })

  // Client-side modals (the cover lightbox): a native <dialog> opened and
  // closed without a server round trip.
  window.addEventListener("stashix:show-modal", (e) => e.target.showModal())
  window.addEventListener("stashix:close-modal", (e) => e.target.closest("dialog")?.close())

  // Success flashes clear themselves; clicking does the same thing sooner.
  window.addEventListener("stashix:flash-shown", (e) => {
    const el = e.target
    setTimeout(() => el.isConnected && el.offsetParent !== null && el.click(), 6000)
  })

  window.addEventListener("stashix:scroll-to", (e) => {
    const el = document.getElementById(e.detail.id)
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" })
  })

  initImagePrefetch()

  // connect if there are any LiveViews on the page
  liveSocket.connect()

  // CSS is render-blocking so by the time this deferred script runs the page is
  // fully styled. Fade out the initial-load cover; fast loads never saw the
  // spinner (500 ms animation-delay), slow loads see it disappear cleanly.
  const stxLoader = document.getElementById("stx-loader")
  if (stxLoader) {
    stxLoader.style.opacity = "0"
    stxLoader.addEventListener("transitionend", () => stxLoader.remove(), { once: true })
  }

  // expose liveSocket on window for web console debug logs and latency simulation:
  // >> liveSocket.enableDebug()
  // >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
  // >> liveSocket.disableLatencySim()
  window.liveSocket = liveSocket
}
