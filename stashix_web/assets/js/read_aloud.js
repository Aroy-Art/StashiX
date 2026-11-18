/*
 * SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

// Read-aloud through the browser's speech synthesis (Web Speech API).
//
// The reader hands over a block of text at a time as segments (sentences),
// each with a callback for when it starts, so the reader can highlight it
// and keep it on screen. One utterance per segment: browsers don't support
// SSML marks and many never fire word boundaries, so this is what keeps
// the highlight in step everywhere. Pausing cancels and later speaks the
// current sentence again: speechSynthesis.pause() is unreliable.
//
// `next()` is asked for the following block when one runs out; it resolves
// to segments, or null at the end of the book.

export const supported = () => typeof window !== "undefined" && "speechSynthesis" in window

export class ReadAloud {
  // onState({playing}) whenever playback starts or stops.
  constructor({next, onState}) {
    this.nextBlock = next
    this.onState = onState
    this.segments = []
    this.index = 0
    this.playing = false
    this.rate = 1
    this.voiceName = null
    this.token = 0
  }

  // Voices for the menu: [{name, lang, default}].
  static voices() {
    if (!supported()) return []
    return speechSynthesis.getVoices().map((v) => ({name: v.name, lang: v.lang, default: v.default}))
  }

  setRate(rate) {
    this.rate = rate
    if (this.playing) this.restart()
  }

  setVoice(name) {
    this.voiceName = name || null
    if (this.playing) this.restart()
  }

  // Starts on these segments (from the reader's spot).
  play(segments) {
    this.segments = segments || []
    this.index = 0
    this.setPlaying(true)
    this.speak()
  }

  resume() {
    if (this.playing) return
    this.setPlaying(true)
    this.speak()
  }

  pause() {
    if (!this.playing) return
    this.token++
    speechSynthesis.cancel()
    this.setPlaying(false)
  }

  stop() {
    this.pause()
    this.segments = []
    this.index = 0
  }

  // Skips a sentence either way.
  skip(by) {
    this.index = Math.max(0, Math.min(this.index + by, this.segments.length))
    if (this.playing) this.restart()
  }

  restart() {
    this.token++
    speechSynthesis.cancel()
    this.speak()
  }

  setPlaying(playing) {
    if (playing === this.playing) return
    this.playing = playing
    this.onState?.({playing})
  }

  async speak() {
    const token = ++this.token
    while (this.index >= this.segments.length) {
      const more = await this.nextBlock()
      if (token !== this.token) return
      if (!more) return this.setPlaying(false)
      this.segments = more
      this.index = 0
    }
    const segment = this.segments[this.index]
    const u = new SpeechSynthesisUtterance(segment.text)
    u.rate = this.rate
    if (segment.lang) u.lang = segment.lang
    const voice = this.voiceName && speechSynthesis.getVoices().find((v) => v.name === this.voiceName)
    if (voice) u.voice = voice
    u.onstart = () => token === this.token && segment.onStart?.()
    u.onend = () => {
      if (token !== this.token) return
      this.index++
      this.speak()
    }
    u.onerror = (e) => {
      if (token !== this.token || e.error === "interrupted" || e.error === "canceled") return
      console.error("ReadAloud:", e.error)
      this.setPlaying(false)
    }
    speechSynthesis.speak(u)
  }
}

// SSML from foliate-js's TTS (one block, <mark name> before each sentence)
// to segments: the text after each mark, with its name.
export const ssmlSegments = (ssml) => {
  const doc = new DOMParser().parseFromString(ssml, "application/xml")
  const root = doc.documentElement
  const lang = root.getAttribute("xml:lang") || root.getAttribute("lang") || null
  const segments = []
  let current = {mark: null, text: ""}
  const walk = (node) => {
    for (const child of node.childNodes) {
      if (child.nodeType === 3) current.text += child.nodeValue
      else if (child.nodeType === 1 && child.localName === "mark") {
        segments.push(current)
        current = {mark: child.getAttribute("name"), text: ""}
      } else if (child.nodeType === 1) walk(child)
    }
  }
  walk(root)
  segments.push(current)
  return segments
    .map((s) => ({...s, text: s.text.replace(/\s+/g, " ").trim(), lang}))
    .filter((s) => /[\p{L}\p{N}]/u.test(s.text))
}

// Sentences of plain text (a PDF page), by the browser's segmenter.
export const sentences = (text, lang) => {
  const seg = typeof Intl.Segmenter === "function" ? new Intl.Segmenter(lang || undefined, {granularity: "sentence"}) : null
  const parts = seg ? [...seg.segment(text)].map((s) => s.segment) : text.split(/(?<=[.!?])\s+/)
  return parts.map((t) => t.replace(/\s+/g, " ").trim()).filter((t) => /[\p{L}\p{N}]/u.test(t))
}
