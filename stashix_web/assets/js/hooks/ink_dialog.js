// InkDialog: opens a <.dialog> as a native modal and turns every way of
// dismissing it (Escape, the close button, a click on the backdrop) into the
// JS command in data-on-close. The server closes it by removing the element.
const InkDialog = {
  mounted() {
    const el = this.el
    const requestClose = () => this.liveSocket.execJS(el, el.dataset.onClose)

    el.addEventListener("cancel", (e) => {
      e.preventDefault()
      requestClose()
    })
    // A backdrop click targets the <dialog> itself. Require the press to
    // start there too, so dragging a text selection out does not close it.
    let pressedOnBackdrop = false
    el.addEventListener("pointerdown", (e) => (pressedOnBackdrop = e.target === el))
    el.addEventListener("click", (e) => {
      if (e.target.closest("[data-dialog-close]")) return requestClose()
      if (e.target === el && pressedOnBackdrop) requestClose()
    })

    if (!el.open) el.showModal()
  },
}

export default InkDialog
