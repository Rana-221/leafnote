const PREFIX = 'leafnote.note.'
const GROUPS_PREFIX = 'leafnote.cachedGroups.'
const DIRECTORY_PREFIX = 'leafnote.cachedDirectory.'
const PROFILE_PREFIX = 'leafnote.cachedProfile.'
const MAX_CACHE = 40

function key(id) {
  return `${PREFIX}${id}`
}

export function cacheNote(note) {
  if (!note?.id) return
  try {
    const payload = {
      id: note.id,
      group_id: note.group_id,
      folder_id: note.folder_id,
      title: note.title,
      content: note.content,
      created_by: note.created_by,
      updated_at: note.updated_at,
      cached_at: new Date().toISOString()
    }
    localStorage.setItem(key(note.id), JSON.stringify(payload))
    trimCache()
  } catch {
    // Quota or private mode: caching is best-effort only.
  }
}

export function readCachedNote(id) {
  if (!id) return null
  try {
    const raw = localStorage.getItem(key(id))
    if (!raw) return null
    const parsed = JSON.parse(raw)
    return parsed && parsed.id === id ? parsed : null
  } catch {
    return null
  }
}

export function removeCachedNote(id) {
  try {
    localStorage.removeItem(key(id))
  } catch {
    // ignore
  }
}

export function cacheProfile(userId, profile) {
  if (!userId || !profile) return
  try {
    localStorage.setItem(
      `${PROFILE_PREFIX}${userId}`,
      JSON.stringify({ profile, cached_at: new Date().toISOString() })
    )
  } catch {
    // ignore
  }
}

export function readCachedProfile(userId) {
  if (!userId) return null
  try {
    const parsed = JSON.parse(localStorage.getItem(`${PROFILE_PREFIX}${userId}`) || 'null')
    return parsed?.profile || null
  } catch {
    return null
  }
}

export function cacheGroups(userId, groups) {
  if (!userId) return
  try {
    localStorage.setItem(
      `${GROUPS_PREFIX}${userId}`,
      JSON.stringify({ groups, cached_at: new Date().toISOString() })
    )
  } catch {
    // ignore
  }
}

export function readCachedGroups(userId) {
  if (!userId) return []
  try {
    const parsed = JSON.parse(localStorage.getItem(`${GROUPS_PREFIX}${userId}`) || 'null')
    return Array.isArray(parsed?.groups) ? parsed.groups : []
  } catch {
    return []
  }
}

export function cacheDirectory(userId, groupId, { folders, notes }) {
  if (!userId || !groupId) return
  try {
    localStorage.setItem(
      `${DIRECTORY_PREFIX}${userId}.${groupId}`,
      JSON.stringify({
        folders: folders || [],
        notes: notes || [],
        cached_at: new Date().toISOString()
      })
    )
  } catch {
    // ignore
  }
}

export function readCachedDirectory(userId, groupId) {
  if (!userId || !groupId) return null
  try {
    const parsed = JSON.parse(
      localStorage.getItem(`${DIRECTORY_PREFIX}${userId}.${groupId}`) || 'null'
    )
    if (!Array.isArray(parsed?.folders) || !Array.isArray(parsed?.notes)) return null
    return parsed
  } catch {
    return null
  }
}

export function clearGroupCache(userId, groupId) {
  clearGroupNoteCache(groupId)
  if (!userId || !groupId) return
  try {
    localStorage.removeItem(`${DIRECTORY_PREFIX}${userId}.${groupId}`)
  } catch {
    // ignore
  }
}

export function clearUserCache(userId) {
  clearNoteCache()
  if (!userId) return
  try {
    const names = []
    for (let i = 0; i < localStorage.length; i += 1) {
      const name = localStorage.key(i)
      if (
        name?.startsWith(`${GROUPS_PREFIX}${userId}`) ||
        name?.startsWith(`${DIRECTORY_PREFIX}${userId}.`) ||
        name?.startsWith(`${PROFILE_PREFIX}${userId}`)
      ) {
        names.push(name)
      }
    }
    names.forEach((name) => localStorage.removeItem(name))
  } catch {
    // ignore
  }
}

export function clearNoteCache() {
  try {
    const names = []
    for (let i = 0; i < localStorage.length; i += 1) {
      const name = localStorage.key(i)
      if (name?.startsWith(PREFIX)) names.push(name)
    }
    names.forEach((name) => localStorage.removeItem(name))
  } catch {
    // ignore
  }
}

export function clearGroupNoteCache(groupId) {
  if (!groupId) return
  try {
    const names = []
    for (let i = 0; i < localStorage.length; i += 1) {
      const name = localStorage.key(i)
      if (!name?.startsWith(PREFIX)) continue
      try {
        const parsed = JSON.parse(localStorage.getItem(name))
        if (parsed?.group_id === groupId) names.push(name)
      } catch {
        // ignore malformed entries
      }
    }
    names.forEach((name) => localStorage.removeItem(name))
  } catch {
    // ignore
  }
}

function trimCache() {
  const entries = []
  for (let i = 0; i < localStorage.length; i += 1) {
    const name = localStorage.key(i)
    if (!name?.startsWith(PREFIX)) continue
    try {
      const parsed = JSON.parse(localStorage.getItem(name))
      entries.push({ name, cachedAt: new Date(parsed.cached_at || 0).getTime() })
    } catch {
      entries.push({ name, cachedAt: 0 })
    }
  }
  if (entries.length <= MAX_CACHE) return
  entries
    .sort((a, b) => a.cachedAt - b.cachedAt)
    .slice(0, entries.length - MAX_CACHE)
    .forEach((entry) => localStorage.removeItem(entry.name))
}
