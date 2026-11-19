import { createClient } from '@supabase/supabase-js'

const url = (import.meta.env.VITE_SUPABASE_URL || '').trim()
const anonKey = (import.meta.env.VITE_SUPABASE_ANON_KEY || '').trim()

function isValidSupabaseUrl(value) {
  try {
    const parsed = new URL(value)
    // Hosted/custom Supabase domains use HTTPS. The Supabase CLI serves a
    // local development API over HTTP on localhost only.
    return (
      parsed.protocol === 'https:' ||
      (parsed.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(parsed.hostname))
    )
  } catch {
    return false
  }
}

export const isSupabaseConfigured =
  isValidSupabaseUrl(url) &&
  anonKey.length > 20 &&
  !url.includes('your-project-ref') &&
  !anonKey.includes('your-anon-key')

export const supabase = isSupabaseConfigured
  ? createClient(url, anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      },
      global: {
        headers: { 'x-application-name': 'leafnote' }
      }
    })
  : null
