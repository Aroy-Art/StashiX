// BlurHash decoder — MIT, adapted from https://github.com/woltapp/blurhash
;(function(w) {
  const CHARS = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~'
  const d83 = s => [...s].reduce((v, c) => v * 83 + CHARS.indexOf(c), 0)
  const lin = v => { const f = v / 255; return f <= 0.04045 ? f / 12.92 : Math.pow((f + 0.055) / 1.055, 2.4) }
  const srgb = v => { v = Math.max(0, Math.min(1, v)); return v <= 0.0031308 ? v * 12.92 * 255 + 0.5 | 0 : (1.055 * Math.pow(v, 1 / 2.4) - 0.055) * 255 + 0.5 | 0 }
  const sp = v => (v < 0 ? -1 : 1) * v * v

  w.decodeBlurhash = function(hash, canvas) {
    if (!hash || hash.length < 6) return
    const sf = d83(hash[0])
    const yC = (sf / 9 | 0) + 1
    const xC = sf % 9 + 1
    const maxAC = (d83(hash[1]) + 1) / 166

    const cols = []
    const dc = d83(hash.slice(2, 6))
    cols.push([lin(dc >> 16), lin((dc >> 8) & 255), lin(dc & 255)])
    for (let i = 1; i < xC * yC; i++) {
      const v = d83(hash.slice(4 + i * 2, 6 + i * 2))
      const qR = v / 361 | 0
      const qG = (v / 19 | 0) % 19
      const qB = v % 19
      cols.push([sp((qR - 9) / 9) * maxAC, sp((qG - 9) / 9) * maxAC, sp((qB - 9) / 9) * maxAC])
    }

    const W = canvas.width, H = canvas.height
    const ctx = canvas.getContext('2d')
    const img = ctx.createImageData(W, H)
    const data = img.data

    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let r = 0, g = 0, b = 0
        for (let j = 0; j < yC; j++) {
          for (let i = 0; i < xC; i++) {
            const bf = Math.cos(Math.PI * x * i / W) * Math.cos(Math.PI * y * j / H)
            const c = cols[j * xC + i]
            r += c[0] * bf; g += c[1] * bf; b += c[2] * bf
          }
        }
        const o = (y * W + x) * 4
        data[o] = srgb(r); data[o + 1] = srgb(g); data[o + 2] = srgb(b); data[o + 3] = 255
      }
    }
    ctx.putImageData(img, 0, 0)
  }
})(window)
