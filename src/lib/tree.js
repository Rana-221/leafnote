const collator = new Intl.Collator('zh-CN', { numeric: true, sensitivity: 'base' })

export function buildTree(folders, notes) {
  const folderMap = new Map()
  const sortedFolders = [...folders].sort((a, b) => collator.compare(a.name, b.name))
  const sortedNotes = [...notes].sort((a, b) => {
    const aTime = new Date(a.updated_at || 0).getTime()
    const bTime = new Date(b.updated_at || 0).getTime()
    if (aTime !== bTime) return bTime - aTime
    return collator.compare(a.title || '', b.title || '')
  })

  for (const folder of sortedFolders) {
    folderMap.set(folder.id, { ...folder, children: [], notes: [] })
  }

  const roots = []
  for (const folder of folderMap.values()) {
    const parent = folder.parent_id ? folderMap.get(folder.parent_id) : null
    if (parent && parent.id !== folder.id) parent.children.push(folder)
    else roots.push(folder)
  }

  const rootNotes = []
  for (const note of sortedNotes) {
    const parent = note.folder_id ? folderMap.get(note.folder_id) : null
    if (parent) parent.notes.push(note)
    else rootNotes.push(note)
  }

  return { roots, folderMap, rootNotes }
}

export function collectFolderIds(folders) {
  return folders.map((folder) => folder.id)
}

export function folderPath(folderId, folderMap) {
  const parts = []
  let current = folderMap.get(folderId)
  let guard = 0
  while (current && guard < 100) {
    parts.unshift(current.name)
    current = current.parent_id ? folderMap.get(current.parent_id) : null
    guard += 1
  }
  return parts.join(' / ')
}

export function countTreeNotes(folder) {
  return folder.notes.length + folder.children.reduce((sum, child) => sum + countTreeNotes(child), 0)
}
