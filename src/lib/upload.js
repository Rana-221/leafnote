import { supabase } from './supabase'

const MAX_INPUT_BYTES = 8 * 1024 * 1024
const ALLOWED = ['image/jpeg', 'image/png', 'image/webp']

function loadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const image = new Image()
    image.onload = () => {
      URL.revokeObjectURL(url)
      resolve(image)
    }
    image.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error('图片读取失败'))
    }
    image.src = url
  })
}

export async function prepareAvatar(file) {
  if (!file) throw new Error('请选择图片')
  if (!ALLOWED.includes(file.type)) {
    throw new Error('仅支持 JPG、PNG 或 WebP 图片')
  }
  if (file.size > MAX_INPUT_BYTES) {
    throw new Error('图片不能超过 8MB')
  }

  const image = await loadImage(file)
  const maxSide = 512
  const ratio = Math.min(1, maxSide / Math.max(image.width, image.height))
  const width = Math.max(1, Math.round(image.width * ratio))
  const height = Math.max(1, Math.round(image.height * ratio))
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const context = canvas.getContext('2d')
  context.fillStyle = '#f7f4ec'
  context.fillRect(0, 0, width, height)
  context.drawImage(image, 0, 0, width, height)

  const blob = await new Promise((resolve) =>
    canvas.toBlob(resolve, 'image/webp', 0.86)
  )
  if (!blob) throw new Error('图片处理失败，请尝试其他图片')
  if (blob.size > 2 * 1024 * 1024) throw new Error('压缩后的图片仍然过大')
  return blob
}

const EXTENSIONS = {
  'image/webp': 'webp',
  'image/png': 'png',
  'image/jpeg': 'jpg'
}

export async function uploadAvatar(userId, file) {
  const blob = await prepareAvatar(file)
  const mime = EXTENSIONS[blob.type] ? blob.type : 'image/jpeg'
  const extension = EXTENSIONS[mime]
  const path = `${userId}/avatar-${Date.now()}.${extension}`
  const { error } = await supabase.storage.from('avatars').upload(path, blob, {
    contentType: mime,
    cacheControl: '3600',
    upsert: false
  })
  if (error) throw error
  return path
}

export async function deleteAvatar(path) {
  if (!path || /^https?:\/\//i.test(path)) return
  await supabase.storage.from('avatars').remove([path])
}
