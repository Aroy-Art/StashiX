/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// The floating bar the readers show over a selection or a highlight:
// four colours, note, copy and (for one already made) delete. The hook that
// owns it decides what each action does; the bar only lays itself out
// above (or, with no room, below) the box it is given.

export const HIGHLIGHT_COLORS = {
  yellow: "#facc15",
  green: "#4ade80",
  blue: "#38bdf8",
  pink: "#f472b6",
}

const LABELS = {yellow: "Yellow", green: "Green", blue: "Blue", pink: "Pink"}
const GAP = 10
const EDGE = 8
const TOP_BAR = 56

// Lucide icons (pencil, copy, trash), inline like the server's <.icon>.
const ICONS = {
  note: '<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/><path d="m15 5 4 4"/>',
  copy: '<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
  delete:
    '<path d="M10 11v6"/><path d="M14 11v6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
}
const icon = (name) =>
  `<svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`

export class AnnotationBar {
  // `host` is a positioned element the bar is placed in; `onAction(action,
  // color)` gets "color" | "note" | "copy" | "delete".
  constructor(host, onAction) {
    this.host = host
    this.onAction = onAction
    this.mode = null
    this.annotation = null
    this.el = document.createElement("div")
    this.el.className = "annot-bar"
    this.el.hidden = true
    this.el.setAttribute("role", "toolbar")
    this.el.setAttribute("aria-label", "Highlight")
    this.el.innerHTML = `
      <div class="annot-bar-colors">
        ${Object.entries(HIGHLIGHT_COLORS)
          .map(([c, hex]) => `<button type="button" data-color="${c}" title="${LABELS[c]}" aria-label="${LABELS[c]}" style="--c:${hex}"></button>`)
          .join("")}
      </div>
      <span class="annot-bar-sep"></span>
      <button type="button" data-action="note" title="Note">${icon("note")}<span>Note</span></button>
      <button type="button" data-action="copy" title="Copy">${icon("copy")}</button>
      <button type="button" data-action="delete" title="Delete" class="annot-bar-delete">${icon("delete")}</button>
    `
    // Keep the selection: a press on the bar must not clear it first.
    this.el.addEventListener("pointerdown", (e) => e.preventDefault())
    this.el.addEventListener("click", (e) => {
      e.stopPropagation()
      const b = e.target.closest("button")
      if (!b) return
      if (b.dataset.color) this.onAction("color", b.dataset.color)
      else this.onAction(b.dataset.action)
    })
    host.append(this.el)
  }

  get visible() {
    return !this.el.hidden
  }

  // `rect` relative to the host's box as it shows (not its scrolled content). Options: mode "new" | "existing",
  // the annotation id and colour for an existing one, copy: false to drop
  // the copy button (image regions).
  show(rect, {mode = "new", annotation = null, color = null, copy = true} = {}) {
    this.mode = mode
    this.annotation = annotation
    this.el.dataset.mode = mode
    this.el.querySelector('[data-action="copy"]').hidden = !copy
    this.el.querySelector('[data-action="delete"]').hidden = mode !== "existing"
    for (const b of this.el.querySelectorAll("[data-color]")) b.toggleAttribute("data-active", b.dataset.color === color)
    this.el.hidden = false

    const host = this.host.getBoundingClientRect()
    const {width, height} = this.el.getBoundingClientRect()
    let left = rect.left + rect.width / 2 - width / 2
    left = Math.max(EDGE, Math.min(left, host.width - width - EDGE))
    let top = rect.top - height - GAP
    if (top < TOP_BAR) top = rect.top + rect.height + GAP
    top = Math.max(TOP_BAR, Math.min(top, host.height - height - EDGE))
    // In a scrolling host the bar is placed in its content.
    this.el.style.left = `${left + this.host.scrollLeft}px`
    this.el.style.top = `${top + this.host.scrollTop}px`
  }

  // True when it was showing.
  hide() {
    if (this.el.hidden) return false
    this.el.hidden = true
    this.mode = null
    this.annotation = null
    return true
  }

  destroy() {
    this.el.remove()
  }
}
