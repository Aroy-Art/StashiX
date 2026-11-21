/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// SortableList: drag to reorder the items of a list or grid.
//
// The hook element wraps the container whose children are the items; each
// item carries data-sort-id. When data-enabled="true", dropping an item
// pushes `data-event` (default "reorder") with {id, index}: the item's id and
// its new place among the items, from 0. The server renders the new order.
//
// SortableJS (~45 KB) is fetched the first time a list mounts. On touch
// screens a long press starts the drag, so the page still scrolls; menus
// and buttons inside an item never start one.

let sortablePromise = null
const loadSortable = () => {
  sortablePromise ||= import("../../vendor/sortable.min").then((mod) => mod.default || mod)
  return sortablePromise
}

const SortableList = {
  mounted() {
    this.setup()
  },

  updated() {
    this.setup()
  },

  destroyed() {
    this.sortable?.destroy()
  },

  async setup() {
    const enabled = this.el.dataset.enabled === "true"
    const container = this.el.firstElementChild
    if (!enabled || !container) {
      this.sortable?.destroy()
      this.sortable = null
      return
    }
    if (this.sortable && this.sortable.el === container) return
    this.sortable?.destroy()

    const Sortable = await loadSortable()
    this.sortable = Sortable.create(container, {
      draggable: "[data-sort-id]",
      filter: "button, [data-menu-panel], input",
      preventOnFilter: false,
      animation: 150,
      delay: 250,
      delayOnTouchOnly: true,
      ghostClass: "sortable-ghost",
      chosenClass: "sortable-chosen",
      onEnd: (e) => {
        if (e.oldIndex === e.newIndex) return
        const items = Array.from(container.querySelectorAll(":scope > [data-sort-id]"))
        const index = items.indexOf(e.item)
        this.pushEvent(this.el.dataset.event || "reorder", {id: e.item.dataset.sortId, index})
      },
    })
  },
}

export default SortableList
