export type ThumbnailSize = 'sx' | 's' | 'm' | 'l' | 'lx'

/** Pick the smallest thumbnail size that covers `logicalPx` at the device's pixel ratio. */
export function thumbnailSize(logicalPx: number): ThumbnailSize {
  const physical = Math.round(logicalPx * (window.devicePixelRatio ?? 1))
  if (physical <= 64)  return 'sx'
  if (physical <= 128) return 's'
  if (physical <= 256) return 'm'
  if (physical <= 512) return 'l'
  return 'lx'
}
