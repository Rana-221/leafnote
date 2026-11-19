import { supabase } from './supabase'

const cache = new Map()
const TTL = 55 * 60 * 1000

export function invalidateAvatar(path) {
  if (path) cache.delete(path)
}

export async function resolveAvatarUrl(path) {
  if (!path) return ''
  if (/^https?:\/\//i.test(path)) return path
  const now = Date.now()
  const existing = cache.get(path)
  if (existing && existing.expiresAt > now) return existing.url

  const { data, error } = await supabase.storage
    .from('avatars')
    .createSignedUrl(path, 3600)

  if (error || !data?.signedUrl) return ''
  cache.set(path, { url: data.signedUrl, expiresAt: now + TTL })
  return data.signedUrl
}
