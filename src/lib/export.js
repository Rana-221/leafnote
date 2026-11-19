import { sanitizeFilename } from './utils'

export function downloadMarkdown(title, content) {
  const filename = `${sanitizeFilename(title)}.md`
  const body = content ?? ''
  const blob = new Blob([body], { type: 'text/markdown;charset=utf-8' })

  // iOS Safari supports the download attribute on same-origin blob URLs in
  // modern versions. Fall back to opening the text if a download is blocked.
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.rel = 'noopener'
  document.body.appendChild(link)
  link.click()
  link.remove()
  window.setTimeout(() => URL.revokeObjectURL(url), 15000)
}
