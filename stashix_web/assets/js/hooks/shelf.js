// Shelf: marks a <.shelf> with data-overflow while its row has more than fits,
// so the arrow buttons only show when there is somewhere to scroll to.
const Shelf = {
  mounted() {
    this.row = this.el.querySelector("[data-shelf-row]")
    this.measure = () => this.el.toggleAttribute("data-overflow", this.row.scrollWidth > this.row.clientWidth + 1)
    this.observer = new ResizeObserver(this.measure)
    this.observer.observe(this.row)
    this.measure()
  },
  // A patch drops the attribute and may add or remove cards.
  updated() {
    this.measure()
  },
  destroyed() {
    this.observer.disconnect()
  },
}

export default Shelf
