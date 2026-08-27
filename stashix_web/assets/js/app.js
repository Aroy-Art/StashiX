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
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

let Hooks = {}

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
      }
    }
    window.addEventListener("keydown", this.handleKey)
  },
  destroyed() {
    window.removeEventListener("keydown", this.handleKey)
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

