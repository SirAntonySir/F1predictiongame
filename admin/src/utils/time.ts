/** Format an ISO timestamp as a human-readable local date+time, or '—' if null. */
export function formatAbsolute(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  })
}

/** Human-readable difference between `iso` and `now` (e.g. "5 min ago", "in 2 h"). */
export function formatRelative(iso: string | null, now: number = Date.now()): string {
  if (!iso) return ''
  const t = new Date(iso).getTime()
  if (Number.isNaN(t)) return ''

  const diffMs = t - now
  const past = diffMs <= 0
  const s = Math.abs(diffMs) / 1000

  const [value, unit] =
    s < 60 ? [Math.round(s), 'sec'] :
    s < 3600 ? [Math.round(s / 60), 'min'] :
    s < 86400 ? [Math.round(s / 3600), 'h'] :
    [Math.round(s / 86400), 'd']

  if (unit === 'sec' && value === 0) return 'just now'
  return past ? `${value} ${unit} ago` : `in ${value} ${unit}`
}
