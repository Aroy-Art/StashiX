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
import SaladUI from "./ui/index.js";
import { SaladUIHook } from "./ui/core/hook.js";

let Hooks = { SaladUI: SaladUIHook }

Hooks.CoverImage = {
  mounted() {
    this.el.style.transition = 'opacity 0.2s ease'
    this.el.style.opacity = '0'
    const reveal = () => { this.el.style.opacity = '1' }
    if (this.el.complete && this.el.naturalWidth > 0) {
      reveal()
    } else {
      this.el.addEventListener('load', reveal, { once: true })
      this.el.addEventListener('error', reveal, { once: true })
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

Hooks.ReaderZoom = {
  mounted() {
    this.zoom = 1
    this.panX = 0
    this.panY = 0
    this.isPanning = false
    this.isPinching = false
    this.panStartX = 0
    this.panStartY = 0
    this.panStartPanX = 0
    this.panStartPanY = 0
    this.lastPinchDist = 0
    this.lastPinchZoom = 1
    this.lastPageSrc = null

    this.pagesEl = document.getElementById("reader-pages")

    // Floating zoom indicator injected outside LiveView's DOM scope
    this.indicator = document.createElement("div")
    this.indicator.style.cssText = [
      "position:fixed", "bottom:56px", "right:16px", "z-index:50",
      "background:rgba(0,0,0,0.75)", "color:#fff", "padding:3px 8px",
      "border-radius:6px", "font-size:12px", "font-family:monospace",
      "pointer-events:auto", "display:none", "cursor:pointer",
      "user-select:none", "border:1px solid rgba(255,255,255,0.15)"
    ].join(";")
    this.indicator.title = "Click to reset zoom (0)"
    this.indicator.addEventListener("click", () => this.applyZoom(1))
    document.body.appendChild(this.indicator)

    this.onWheel = (e) => {
      if (!e.ctrlKey && !e.metaKey) return
      e.preventDefault()
      const rect = this.el.getBoundingClientRect()
      const pivotX = e.clientX - (rect.left + rect.width / 2)
      const pivotY = e.clientY - (rect.top + rect.height / 2)
      const factor = e.deltaY < 0 ? 1.15 : 1 / 1.15
      this.applyZoom(this.zoom * factor, pivotX, pivotY)
    }

    this.onTouchStart = (e) => {
      if (e.touches.length === 2) {
        this.isPinching = true
        this.lastPinchDist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY
        )
        this.lastPinchZoom = this.zoom
      }
    }

    this.onTouchMove = (e) => {
      if (this.isPinching && e.touches.length === 2) {
        e.preventDefault()
        const dist = Math.hypot(
          e.touches[0].clientX - e.touches[1].clientX,
          e.touches[0].clientY - e.touches[1].clientY
        )
        this.applyZoom(this.lastPinchZoom * (dist / this.lastPinchDist))
      }
    }

    this.onTouchEnd = (e) => {
      if (e.touches.length < 2) this.isPinching = false
    }

    this.onPointerDown = (e) => {
      if (this.zoom <= 1.01 || e.button !== 0) return
      this.isPanning = true
      this.panStartX = e.clientX
      this.panStartY = e.clientY
      this.panStartPanX = this.panX
      this.panStartPanY = this.panY
      this.el.setPointerCapture(e.pointerId)
      this.el.style.cursor = "grabbing"
      e.stopPropagation()
    }

    this.onPointerMove = (e) => {
      if (!this.isPanning) return
      this.panX = this.panStartPanX + (e.clientX - this.panStartX) / this.zoom
      this.panY = this.panStartPanY + (e.clientY - this.panStartY) / this.zoom
      this.clampPan()
      this.applyTransform()
    }

    this.onPointerUp = () => {
      if (this.isPanning) {
        this.isPanning = false
        this.el.style.cursor = this.zoom > 1.01 ? "grab" : ""
      }
    }

    this.onZoomIn    = () => this.applyZoom(this.zoom * 1.25)
    this.onZoomOut   = () => this.applyZoom(this.zoom / 1.25)
    this.onZoomReset = () => this.applyZoom(1)

    this.el.addEventListener("wheel", this.onWheel, { passive: false })
    this.el.addEventListener("touchstart", this.onTouchStart, { passive: true })
    this.el.addEventListener("touchmove", this.onTouchMove, { passive: false })
    this.el.addEventListener("touchend", this.onTouchEnd)
    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("pointermove", this.onPointerMove)
    this.el.addEventListener("pointerup", this.onPointerUp)
    window.addEventListener("reader:zoom-in",    this.onZoomIn)
    window.addEventListener("reader:zoom-out",   this.onZoomOut)
    window.addEventListener("reader:zoom-reset", this.onZoomReset)
  },

  updated() {
    const img = this.pagesEl && this.pagesEl.querySelector("img")
    const src = img && img.src
    if (src && src !== this.lastPageSrc) {
      this.lastPageSrc = src
      this.applyZoom(1)
    }
  },

  destroyed() {
    this.el.removeEventListener("wheel", this.onWheel)
    this.el.removeEventListener("touchstart", this.onTouchStart)
    this.el.removeEventListener("touchmove", this.onTouchMove)
    this.el.removeEventListener("touchend", this.onTouchEnd)
    this.el.removeEventListener("pointerdown", this.onPointerDown)
    this.el.removeEventListener("pointermove", this.onPointerMove)
    this.el.removeEventListener("pointerup", this.onPointerUp)
    window.removeEventListener("reader:zoom-in",    this.onZoomIn)
    window.removeEventListener("reader:zoom-out",   this.onZoomOut)
    window.removeEventListener("reader:zoom-reset", this.onZoomReset)
    this.indicator.remove()
  },

  applyZoom(newZoom, pivotX = 0, pivotY = 0) {
    const oldZoom = this.zoom
    const clamped = Math.max(1, Math.min(5, newZoom))
    // Adjust pan so the pivot point stays fixed on screen
    if (clamped !== oldZoom) {
      const factor = 1 / clamped - 1 / oldZoom
      this.panX += pivotX * factor
      this.panY += pivotY * factor
      this.zoom = clamped
    }
    if (this.zoom <= 1.001) {
      this.zoom = 1
      this.panX = 0
      this.panY = 0
    } else {
      this.clampPan()
    }
    this.applyTransform()
    this.updateZones()
    this.updateIndicator()
  },

  clampPan() {
    const rect = this.el.getBoundingClientRect()
    const maxX = rect.width  * (this.zoom - 1) / (2 * this.zoom)
    const maxY = rect.height * (this.zoom - 1) / (2 * this.zoom)
    this.panX = Math.max(-maxX, Math.min(maxX, this.panX))
    this.panY = Math.max(-maxY, Math.min(maxY, this.panY))
  },

  applyTransform() {
    if (this.pagesEl) {
      this.pagesEl.style.transform =
        `scale(${this.zoom}) translate(${this.panX}px, ${this.panY}px)`
    }
  },

  updateZones() {
    const zoomed = this.zoom > 1.01
    this.el.querySelectorAll(".reader-click-zone").forEach(z => {
      z.style.pointerEvents = zoomed ? "none" : ""
    })
    this.el.style.cursor = zoomed ? "grab" : ""
  },

  updateIndicator() {
    if (this.zoom > 1.01) {
      this.indicator.textContent = `${Math.round(this.zoom * 100)}%`
      this.indicator.style.display = "block"
    } else {
      this.indicator.style.display = "none"
    }
  }
}

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

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

