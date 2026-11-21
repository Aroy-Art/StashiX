/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// ClampText: marks a <.clamp_text> with data-overflow when its text runs past
// the line clamp, which reveals the Show more toggle. Measured only while
// collapsed; an expanded block keeps the mark so it can collapse again.
const ClampText = {
  mounted() {
    this.text = this.el.querySelector("p")
    this.observer = new ResizeObserver(() => this.measure())
    this.observer.observe(this.text)
    this.measure()
  },
  updated() {
    this.measure()
  },
  destroyed() {
    this.observer.disconnect()
  },
  measure() {
    if (this.el.hasAttribute("data-expanded")) return
    const overflows = this.text.scrollHeight > this.text.clientHeight + 1
    this.el.toggleAttribute("data-overflow", overflows)
  },
}

export default ClampText
