/**
 * Format series year(s) for display.
 *   single year  (1992)      → "1992"
 *   year range   (2004-2005) → "2004–2005"
 *   ongoing      (2003-)     → "2003–"
 */
export function formatYears(
  startYear?: number,
  endYear?: number,
  ongoing?: boolean,
): string | null {
  if (!startYear) return null
  if (endYear) return `${startYear}–${endYear}`
  if (ongoing) return `${startYear}–`
  return `${startYear}`
}
