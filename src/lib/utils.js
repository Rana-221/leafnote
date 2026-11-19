export function formatDate(value, options = {}) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    ...options
  }).format(date)
}

export function formatDateTime(value) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  return new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit'
  }).format(date)
}

export function relativeTime(value) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  const seconds = Math.round((date.getTime() - Date.now()) / 1000)
  const formatter = new Intl.RelativeTimeFormat('zh-CN', { numeric: 'auto' })
  const abs = Math.abs(seconds)
  if (abs < 60) return formatter.format(seconds, 'second')
  if (abs < 3600) return formatter.format(Math.round(seconds / 60), 'minute')
  if (abs < 86400) return formatter.format(Math.round(seconds / 3600), 'hour')
  if (abs < 86400 * 30) return formatter.format(Math.round(seconds / 86400), 'day')
  return formatDate(value)
}

export function sanitizeFilename(name) {
  return (
    (name || '未命名笔记')
      .replace(/[\\/:*?"<>|\u0000-\u001f]/g, '-')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 120) || '未命名笔记'
  )
}

export function isUsernameValid(username) {
  const value = (username || '').trim()
  return value.length >= 2 && value.length <= 24 && !/[\u0000-\u001f\u007f]/.test(value)
}

export function isEmailValid(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test((email || '').trim())
}

const ERROR_MESSAGES = [
  [/invalid login credentials/i, '邮箱或密码不正确'],
  [/email not confirmed/i, '邮箱尚未验证，请先打开验证邮件中的链接'],
  [/user already registered/i, '该邮箱已注册，请直接登录'],
  [/password should be at least/i, '密码长度不足，请至少使用 8 位密码'],
  [/rate limit/i, '操作过于频繁，请稍后再试'],
  [/database error saving new user/i, '注册失败，请稍后重试或联系管理员'],
  [/signup is disabled/i, '当前项目未开放邮箱注册'],
  [/phone provider/i, 'Supabase 项目尚未配置短信服务，暂时无法绑定手机号'],
  [/sms/i, '短信发送失败，请检查手机号或 Supabase 短信配置'],
  [/invalid.*phone/i, '手机号格式不正确，请使用国际区号格式'],
  [/content-type|mime/i, '文件类型不受支持'],
  [/payload too large|exceeded the maximum/i, '文件过大，请选择 2MB 以内的图片'],
  [/JWT|not authenticated|auth required/i, '登录状态已失效，请重新登录'],
  [/row-level security|permission denied/i, '没有执行此操作的权限'],
  [/duplicate key.*profiles_username/i, '这个用户名已被使用，请换一个'],
  [/duplicate key/i, '数据已存在，请勿重复操作'],
  [/FOLDER_CYCLE/i, '不能把文件夹移动到它自己的子文件夹中'],
  [/PARENT_FOLDER_INVALID|NOTE_FOLDER_INVALID/i, '文件夹不属于当前群组'],
  [/INVITE_NOT_FOUND/i, '邀请码不存在'],
  [/INVITE_REVOKED/i, '邀请码已被撤销'],
  [/INVITE_EXPIRED/i, '邀请码已过期'],
  [/INVITE_EXHAUSTED/i, '邀请码使用次数已用完'],
  [/OWNER_MUST_TRANSFER/i, '群主需要先转让群组才能退出'],
  [/OWNER_REQUIRED/i, '只有群主可以执行此操作'],
  [/ADMIN_REQUIRED/i, '需要管理员权限'],
  [/CANNOT_REMOVE_OWNER/i, '不能移除群主'],
  [/CANNOT_CHANGE_OWNER_ROLE/i, '不能修改群主角色'],
  [/ALREADY_OWNER/i, '对方已经是群主'],
  [/NetworkError|Failed to fetch|fetch failed/i, '网络连接失败，请检查网络后重试']
]

export function errorMessage(error, fallback = '操作失败，请稍后重试') {
  if (!error) return fallback
  const raw = [error.message, error.error_description, error.details, error.hint]
    .filter(Boolean)
    .join(' ')
  for (const [pattern, message] of ERROR_MESSAGES) {
    if (pattern.test(raw)) return message
  }
  return (error.message && String(error.message)) || fallback
}

export function bytesToSize(bytes) {
  if (!bytes) return '0 B'
  const units = ['B', 'KB', 'MB']
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  return `${(bytes / 1024 ** index).toFixed(index ? 1 : 0)} ${units[index]}`
}

export function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    return navigator.clipboard.writeText(text)
  }
  return new Promise((resolve, reject) => {
    const textarea = document.createElement('textarea')
    textarea.value = text
    textarea.setAttribute('readonly', '')
    textarea.style.position = 'fixed'
    textarea.style.left = '-9999px'
    document.body.appendChild(textarea)
    textarea.select()
    try {
      document.execCommand('copy') ? resolve() : reject(new Error('copy failed'))
    } catch (error) {
      reject(error)
    } finally {
      document.body.removeChild(textarea)
    }
  })
}

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}
