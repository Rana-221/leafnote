import { reactive } from 'vue'

let seq = 0
export const toasts = reactive([])

function remove(id) {
  const index = toasts.findIndex((item) => item.id === id)
  if (index >= 0) toasts.splice(index, 1)
}

function push(type, message, duration = 3600) {
  const text = typeof message === 'string' ? message : String(message?.message || message)
  if (!text) return
  const id = ++seq
  toasts.push({ id, type, message: text })
  if (toasts.length > 4) toasts.shift()
  window.setTimeout(() => remove(id), duration)
}

export const toast = {
  success: (message, duration) => push('success', message, duration),
  error: (message, duration = 5200) => push('error', message, duration),
  info: (message, duration) => push('info', message, duration),
  remove
}
