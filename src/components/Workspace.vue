<template>
  <div class="workspace">
    <div class="mobile-sidebar-backdrop" :class="{ visible: sidebarOpen }" @click="sidebarOpen = false"></div>

    <AppSidebar
      :profile="profile"
      :groups="groups"
      :active-group="activeGroup"
      :group-role="groupRole"
      :tree="tree"
      :expanded="expanded"
      :active-note-id="activeNoteId"
      :active-folder-id="activeFolderId"
      :current-user-id="uid"
      :mobile-open="sidebarOpen"
      @close-mobile="sidebarOpen = false"
      @select-group="selectGroup"
      @create-group="openCreateGroup"
      @join-group="openJoinGroup()"
      @open-group-settings="openGroupSettings('members')"
      @open-profile="profileOpen = true"
      @sign-out="signOut"
      @refresh="refreshDirectory"
      @toggle-folder="toggleFolder"
      @select-folder="selectFolder"
      @select-note="openNote"
      @create-note="createNote"
      @add-folder="openCreateFolder"
      @rename-folder="openRenameFolder"
      @delete-folder="deleteFolder"
    />

    <main class="workspace-main">
      <div v-if="bootLoading" class="workspace-boot">
        <div class="brand-mark large"><AppIcon name="leaf" :size="28" /></div>
        <div class="boot-spinner"></div>
        <p>正在整理你的书桌…</p>
      </div>

      <template v-else-if="!activeGroup">
        <header class="mobile-topbar">
          <button class="icon-btn mobile-menu-btn" type="button" aria-label="打开目录" @click="sidebarOpen = true">
            <AppIcon name="menu" :size="19" />
          </button>
          <span class="mobile-brand"><AppIcon name="leaf" :size="18" /> 轻笺</span>
        </header>
        <section class="workspace-empty">
          <div class="empty-illustration">
            <span class="empty-leaf"><AppIcon name="leaf" :size="44" /></span>
          </div>
          <p class="eyebrow">YOUR OWN QUIET SPACE</p>
          <h1>开始写下第一行</h1>
          <p class="empty-lead">
            创建一个群组，把笔记安放在自己的小天地里；<br class="desktop-only" />
            也可以使用邀请码加入朋友的群组。
          </p>
          <div class="empty-actions">
            <button class="btn btn-primary" type="button" @click="openCreateGroup">
              <AppIcon name="plus" :size="17" /> 新建群组
            </button>
            <button class="btn btn-secondary" type="button" @click="openJoinGroup()">
              <AppIcon name="key" :size="17" /> 使用邀请码
            </button>
          </div>
          <div class="empty-features">
            <div><AppIcon name="shield" :size="17" /><span>RLS 数据库隔离</span></div>
            <div><AppIcon name="folder" :size="17" /><span>无限层级目录</span></div>
            <div><AppIcon name="cloud" :size="17" /><span>自动同步</span></div>
          </div>
        </section>
      </template>

      <template v-else>
        <div v-if="loadingData || noteLoading" class="workspace-loading">
          <header class="mobile-topbar">
            <button class="icon-btn mobile-menu-btn" type="button" aria-label="打开目录" @click="sidebarOpen = true">
              <AppIcon name="menu" :size="19" />
            </button>
            <span class="mobile-brand">{{ activeGroup.name }}</span>
          </header>
          <div class="loading-pane">
            <div class="skeleton skeleton-title"></div>
            <div class="skeleton skeleton-line wide"></div>
            <div class="skeleton skeleton-line"></div>
            <div class="skeleton skeleton-block"></div>
          </div>
        </div>

        <NoteEditor
          v-else-if="activeNote"
          :note="activeNote"
          :draft="draft"
          :note-id="activeNote.id"
          :author-name="activeAuthorName"
          :current-user-id="uid"
          :read-only="readOnly"
          :save-state="saveState"
          :last-saved-at="lastSavedAt"
          @update-title="updateTitle"
          @update-content="updateContent"
          @title-blur="onTitleBlur"
          @export="exportNote"
          @delete="deleteNote"
          @open-sidebar="sidebarOpen = true"
        />

        <section v-else class="group-welcome">
          <header class="mobile-topbar">
            <button class="icon-btn mobile-menu-btn" type="button" aria-label="打开目录" @click="sidebarOpen = true">
              <AppIcon name="menu" :size="19" />
            </button>
            <span class="mobile-brand">{{ activeGroup.name }}</span>
          </header>

          <div class="group-welcome-inner">
            <div class="group-welcome-head">
              <div>
                <p class="eyebrow">GROUP WORKSPACE</p>
                <h1>{{ activeGroup.name }}</h1>
                <p class="welcome-meta">
                  <span class="role-pill" :class="`role-${groupRole}`">{{ groupRole === 'admin' ? '管理员' : '普通组员' }}</span>
                  <span>{{ notes.length }} 条笔记 · {{ folders.length }} 个文件夹</span>
                </p>
              </div>
              <button class="btn btn-secondary btn-sm" type="button" @click="openGroupSettings('members')">
                <AppIcon name="settings" :size="15" /> 群组管理
              </button>
            </div>

            <div class="quick-actions">
              <button class="quick-action" type="button" @click="createNote(activeFolderId || null)">
                <span class="quick-icon"><AppIcon name="plus" :size="19" /></span>
                <span><strong>新建笔记</strong><small>立即开始书写</small></span>
                <AppIcon name="arrow-right" :size="16" class="quick-arrow" />
              </button>
              <button class="quick-action" type="button" @click="openCreateFolder(activeFolderId || null)">
                <span class="quick-icon folder"><AppIcon name="folder" :size="19" /></span>
                <span><strong>新建文件夹</strong><small>整理你的思路</small></span>
                <AppIcon name="arrow-right" :size="16" class="quick-arrow" />
              </button>
              <button class="quick-action" type="button" @click="openGroupSettings('invites')">
                <span class="quick-icon invite"><AppIcon name="qr-code" :size="19" /></span>
                <span><strong>邀请组员</strong><small>生成邀请码或二维码</small></span>
                <AppIcon name="arrow-right" :size="16" class="quick-arrow" />
              </button>
            </div>

            <section v-if="recentNotes.length" class="recent-notes">
              <div class="section-heading">
                <h2>最近编辑</h2>
                <button class="text-link" type="button" @click="refreshDirectory">刷新</button>
              </div>
              <div class="recent-list">
                <button v-for="note in recentNotes" :key="note.id" class="recent-item" type="button" @click="openNote(note)">
                  <span class="recent-icon"><AppIcon name="note" :size="17" /></span>
                  <span class="recent-main">
                    <strong>{{ note.title || '未命名笔记' }}</strong>
                    <small>{{ relativeTime(note.updated_at) }} · {{ note.folder_id ? '文件夹内' : '根目录' }}</small>
                  </span>
                  <AppIcon name="chevron-right" :size="16" class="recent-arrow" />
                </button>
              </div>
            </section>

            <div v-else class="welcome-empty-note">
              <span class="welcome-note-icon"><AppIcon name="note" :size="26" /></span>
              <div>
                <strong>这个群组还没有笔记</strong>
                <p>创建第一条笔记，目录树会自动出现在左侧。</p>
              </div>
              <button class="btn btn-primary btn-sm" type="button" @click="createNote(null)">写第一条</button>
            </div>

            <div class="security-note">
              <AppIcon name="shield" :size="18" />
              <div>
                <strong>隐私与脚本安全</strong>
                <p>
                  群组数据由 Supabase RLS 隔离；实名信息只按群组设置展示。
                  自定义脚本只在笔记作者本人查看时运行，并隔离在 <code>sandbox="allow-scripts"</code> iframe 中。
                </p>
              </div>
            </div>
          </div>
        </section>
      </template>
    </main>

    <ProfileDialog
      :open="profileOpen"
      :session="session"
      :profile="profile"
      @close="profileOpen = false"
      @updated="handleProfileUpdated"
    />

    <GroupDialog
      v-if="activeGroup"
      :open="groupDialogOpen"
      :group="activeGroup"
      :session="session"
      :initial-tab="groupDialogTab"
      @close="groupDialogOpen = false"
      @changed="handleGroupChanged"
      @left="handleGroupLeft"
    />

    <JoinGroupDialog
      :open="joinDialogOpen"
      :initial-code="joinInitialCode"
      @close="joinDialogOpen = false; joinInitialCode = ''"
      @joined="handleJoinedGroup"
    />

    <ModalDialog
      :open="createGroupOpen"
      title="新建群组"
      subtitle="群组之间的所有数据完全隔离"
      size="sm"
      @close="createGroupOpen = false"
    >
      <form id="create-group-form" class="dialog-form" @submit.prevent="createGroup">
        <label class="field">
          <span>群组名称</span>
          <input v-model="createGroupName" type="text" maxlength="60" placeholder="例如：设计组、读书会" required autofocus />
          <small class="field-hint">你可以创建无限多个群组。</small>
        </label>
        <div class="info-box compact">
          <AppIcon name="shield" :size="16" />
          <p>创建后你是群主和管理员，可以邀请成员、调整实名可见性并转让群组。</p>
        </div>
      </form>
      <template #footer>
        <button class="btn btn-ghost" type="button" @click="createGroupOpen = false">取消</button>
        <button class="btn btn-primary" type="submit" form="create-group-form" :disabled="createGroupBusy">
          <AppIcon v-if="createGroupBusy" name="loader" :size="16" class="spin" />
          {{ createGroupBusy ? '创建中…' : '创建群组' }}
        </button>
      </template>
    </ModalDialog>

    <ModalDialog
      :open="folderDialog.open"
      :title="folderDialog.mode === 'rename' ? '重命名文件夹' : '新建文件夹'"
      :subtitle="folderDialogParentPath"
      size="sm"
      @close="folderDialog.open = false"
    >
      <form id="folder-form" class="dialog-form" @submit.prevent="submitFolder">
        <label class="field">
          <span>文件夹名称</span>
          <input
            v-model="folderDialog.name"
            type="text"
            maxlength="80"
            placeholder="文件夹名称"
            required
            autofocus
          />
          <small class="field-hint">支持无限层级嵌套，可在文件夹上继续新建子文件夹。</small>
        </label>
      </form>
      <template #footer>
        <button class="btn btn-ghost" type="button" @click="folderDialog.open = false">取消</button>
        <button class="btn btn-primary" type="submit" form="folder-form" :disabled="folderDialog.busy">
          <AppIcon v-if="folderDialog.busy" name="loader" :size="16" class="spin" />
          {{ folderDialog.busy ? '保存中…' : '保存' }}
        </button>
      </template>
    </ModalDialog>
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import AppIcon from './AppIcon.vue'
import AppSidebar from './AppSidebar.vue'
import GroupDialog from './GroupDialog.vue'
import JoinGroupDialog from './JoinGroupDialog.vue'
import ModalDialog from './ModalDialog.vue'
import NoteEditor from './NoteEditor.vue'
import ProfileDialog from './ProfileDialog.vue'
import { supabase } from '../lib/supabase'
import { buildTree, folderPath } from '../lib/tree'
import {
  cacheDirectory,
  cacheGroups,
  cacheNote,
  cacheProfile,
  clearGroupCache,
  clearUserCache,
  readCachedDirectory,
  readCachedGroups,
  readCachedNote,
  readCachedProfile,
  removeCachedNote
} from '../lib/cache'
import { downloadMarkdown } from '../lib/export'
import { errorMessage, relativeTime, sleep } from '../lib/utils'
import { toast } from '../lib/toast'

const props = defineProps({
  session: { type: Object, required: true }
})
const emit = defineEmits(['signed-out'])

const uid = computed(() => props.session.user.id)
const profile = ref(null)
const groups = ref([])
const activeGroupId = ref('')
const activeGroup = computed(() => groups.value.find((group) => group.id === activeGroupId.value) || null)
const groupRole = computed(() => activeGroup.value?.role || 'member')
const isAdmin = computed(() => groupRole.value === 'admin')

const folders = ref([])
const notes = ref([])
const expanded = ref(new Set())
const activeFolderId = ref('')
const activeNote = ref(null)
const activeNoteId = ref('')
const draft = reactive({ title: '', content: '' })
const authorNames = reactive({})

const bootLoading = ref(true)
const loadingData = ref(false)
const noteLoading = ref(false)
const sidebarOpen = ref(false)
const online = ref(navigator.onLine)

const dirty = ref(false)
const saveState = ref('saved')
const lastSavedAt = ref('')
let dirtyVersion = 0
let saveTimer = null
let savingPromise = null
let noteLoadToken = 0
let lastSaveToastAt = 0

const profileOpen = ref(false)
const groupDialogOpen = ref(false)
const groupDialogTab = ref('members')
const joinDialogOpen = ref(false)
const joinInitialCode = ref('')
const createGroupOpen = ref(false)
const createGroupName = ref('')
const createGroupBusy = ref(false)

const folderDialog = reactive({
  open: false,
  mode: 'create',
  parentId: null,
  folder: null,
  name: '',
  busy: false
})

const tree = computed(() => {
  const built = buildTree(folders.value, notes.value)
  return { ...built, notesCount: notes.value.length }
})
const readOnly = computed(() => Boolean(activeNote.value && activeNote.value.created_by !== uid.value))
const activeAuthorName = computed(() => {
  if (!activeNote.value) return ''
  if (activeNote.value.created_by === uid.value) return profile.value?.username || '我'
  return authorNames[activeNote.value.created_by] || '同组组员'
})
const recentNotes = computed(() => notes.value.slice(0, 5))
const folderDialogParentPath = computed(() => {
  if (folderDialog.mode === 'rename') return '修改文件夹名称'
  if (!folderDialog.parentId) return '创建在群组根目录'
  const built = buildTree(folders.value, notes.value)
  const path = folderPath(folderDialog.parentId, built.folderMap)
  return path ? `创建在「${path}」中` : '创建子文件夹'
})

function storageKey(suffix) {
  return `leafnote.${suffix}.${uid.value}`
}

function setActiveGroup(id) {
  activeGroupId.value = id || ''
  try {
    if (id) localStorage.setItem(storageKey('activeGroup'), id)
    else localStorage.removeItem(storageKey('activeGroup'))
  } catch {
    // ignore
  }
}

async function loadProfile() {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const { data, error } = await supabase
      .from('profiles')
      .select('id, username, avatar_path, created_at, updated_at')
      .eq('id', uid.value)
      .maybeSingle()
    if (data) {
      profile.value = data
      cacheProfile(uid.value, data)
      return
    }
    if (error && error.code !== 'PGRST116') break
    await sleep(300)
  }
  const cachedProfile = readCachedProfile(uid.value)
  if (cachedProfile) {
    profile.value = cachedProfile
    return
  }
  profile.value = {
    id: uid.value,
    username: (props.session.user.email || '用户').split('@')[0],
    avatar_path: null
  }
  toast.error('个人资料尚未创建，部分功能可能不可用。请重新登录或检查数据库触发器。')
}

async function reloadGroups(preferredId = null) {
  try {
    const [groupResult, membershipResult] = await Promise.all([
      supabase
        .from('groups')
        .select('id, name, owner_id, real_name_visibility, created_at, updated_at')
        .order('created_at', { ascending: true }),
      supabase
        .from('group_members')
        .select('group_id, role')
        .eq('user_id', uid.value)
    ])
    if (groupResult.error) throw groupResult.error
    if (membershipResult.error) throw membershipResult.error

    const roleMap = Object.fromEntries(
      (membershipResult.data || []).map((row) => [row.group_id, row.role])
    )
    groups.value = (groupResult.data || []).map((group) => ({
      ...group,
      role: roleMap[group.id] || 'member'
    }))
    cacheGroups(uid.value, groups.value)
  } catch (error) {
    if (!groups.value.length) {
      const cached = readCachedGroups(uid.value)
      if (cached.length) {
        groups.value = cached
        const stored = localStorage.getItem(storageKey('activeGroup')) || ''
        const candidate = preferredId || stored
        setActiveGroup(
          cached.some((group) => group.id === candidate) ? candidate : cached[0].id
        )
        toast.info('离线中：使用本机缓存的群组目录')
        return activeGroupId.value
      }
    }
    throw error
  }

  const stored = localStorage.getItem(storageKey('activeGroup')) || ''
  const candidate = preferredId || activeGroupId.value || stored
  const next = groups.value.some((group) => group.id === candidate)
    ? candidate
    : groups.value[0]?.id || ''
  setActiveGroup(next)
  return next
}

function persistDirectoryCache() {
  if (!activeGroupId.value) return
  cacheDirectory(uid.value, activeGroupId.value, {
    folders: folders.value,
    notes: notes.value
  })
}

function resetNoteState() {
  noteLoadToken += 1
  activeNote.value = null
  activeNoteId.value = ''
  draft.title = ''
  draft.content = ''
  dirty.value = false
  dirtyVersion += 1
  saveState.value = 'saved'
  lastSavedAt.value = ''
  noteLoading.value = false
  activeFolderId.value = ''
  try {
    localStorage.removeItem(storageKey('activeNote'))
  } catch {
    // ignore
  }
}

async function loadData(groupId, options = {}) {
  const preserveActive = Boolean(options.preserveActive)
  if (!groupId) return
  const group = groups.value.find((item) => item.id === groupId)
  if (!group) return
  const rememberedBeforeReset =
    localStorage.getItem(storageKey('activeNote')) || ''

  if (!preserveActive) {
    await saveNow()
    resetNoteState()
    loadingData.value = true
    folders.value = []
    notes.value = []
    expanded.value = new Set()
  }

  try {
    const [folderResult, noteResult] = await Promise.all([
      supabase
        .from('folders')
        .select('id, group_id, parent_id, name, created_by, created_at, updated_at')
        .eq('group_id', groupId),
      supabase
        .from('notes')
        .select('id, group_id, folder_id, title, created_by, created_at, updated_at')
        .eq('group_id', groupId)
        .order('updated_at', { ascending: false })
    ])
    if (folderResult.error) throw folderResult.error
    if (noteResult.error) throw noteResult.error

    folders.value = folderResult.data || []
    notes.value = noteResult.data || []
    persistDirectoryCache()
    restoreExpanded(groupId)

    const rememberedId = preserveActive
      ? activeNoteId.value
      : rememberedBeforeReset
    const preferred = notes.value.find((note) => note.id === rememberedId)
    const target = preferred || (preserveActive ? null : notes.value[0] || null)

    if (target) {
      await openNote(target, { skipSave: true, keepSidebar: true, force: preserveActive })
    } else {
      resetNoteState()
    }

    await loadAuthorNames()
  } catch (error) {
    const cached = readCachedDirectory(uid.value, groupId)
    if (cached) {
      folders.value = cached.folders
      notes.value = cached.notes
      restoreExpanded(groupId)
      const preferred = notes.value.find((note) => note.id === rememberedBeforeReset)
      const target = preferred || notes.value[0] || null
      if (target) {
        await openNote(target, { skipSave: true, keepSidebar: true, force: true })
      } else {
        resetNoteState()
      }
      toast.info('离线中：目录来自本机缓存，恢复网络后会自动同步')
    } else {
      toast.error(errorMessage(error, '目录加载失败'))
    }
  } finally {
    loadingData.value = false
  }
}

async function loadAuthorNames() {
  const missing = [
    ...new Set(
      notes.value
        .map((note) => note.created_by)
        .filter((id) => id && id !== uid.value && !authorNames[id])
    )
  ]
  if (!missing.length) return
  const { data, error } = await supabase
    .from('profiles')
    .select('id, username')
    .in('id', missing)
  if (error) return
  for (const item of data || []) authorNames[item.id] = item.username
}

function restoreExpanded(groupId) {
  let stored = null
  try {
    stored = JSON.parse(localStorage.getItem(storageKey(`expanded.${groupId}`)) || 'null')
  } catch {
    stored = null
  }
  const valid = new Set(folders.value.map((folder) => folder.id))
  if (Array.isArray(stored)) {
    expanded.value = new Set(stored.filter((id) => valid.has(id)))
  } else {
    expanded.value = new Set(
      folders.value.filter((folder) => !folder.parent_id).map((folder) => folder.id)
    )
  }
}

function persistExpanded() {
  try {
    localStorage.setItem(
      storageKey(`expanded.${activeGroupId.value}`),
      JSON.stringify([...expanded.value])
    )
  } catch {
    // ignore
  }
}

function toggleFolder(id) {
  const next = new Set(expanded.value)
  if (next.has(id)) next.delete(id)
  else next.add(id)
  expanded.value = next
  persistExpanded()
}

function expandAncestors(folderId) {
  if (!folderId) return
  const map = new Map(folders.value.map((folder) => [folder.id, folder]))
  const next = new Set(expanded.value)
  let current = map.get(folderId)
  let guard = 0
  while (current && guard < 100) {
    next.add(current.id)
    current = current.parent_id ? map.get(current.parent_id) : null
    guard += 1
  }
  expanded.value = next
  persistExpanded()
}

function selectFolder(folderId) {
  activeFolderId.value = folderId || ''
  sidebarOpen.value = false
}

async function openNote(summary, options = {}) {
  if (!summary) return
  if (!options.force && activeNoteId.value === summary.id && activeNote.value) {
    sidebarOpen.value = false
    return
  }
  if (!options.skipSave) await saveNow()

  const token = ++noteLoadToken
  noteLoading.value = true
  activeNote.value = null
  activeNoteId.value = summary.id
  draft.title = summary.title || ''
  draft.content = ''
  dirty.value = false
  dirtyVersion += 1
  saveState.value = 'saved'

  try {
    const { data, error } = await supabase
      .from('notes')
      .select('*')
      .eq('id', summary.id)
      .maybeSingle()
    if (token !== noteLoadToken) return
    if (error) throw error
    if (!data) throw new Error('笔记不存在或没有访问权限')

    activeNote.value = data
    activeNoteId.value = data.id
    draft.title = data.title
    draft.content = data.content || ''
    dirty.value = false
    dirtyVersion += 1
    saveState.value = 'saved'
    lastSavedAt.value = data.updated_at
    activeFolderId.value = data.folder_id || ''
    cacheNote(data)
    expandAncestors(data.folder_id)
    try {
      localStorage.setItem(storageKey('activeNote'), data.id)
    } catch {
      // ignore
    }
    if (data.created_by !== uid.value && !authorNames[data.created_by]) {
      const { data: author } = await supabase
        .from('profiles')
        .select('username')
        .eq('id', data.created_by)
        .maybeSingle()
      if (token === noteLoadToken) {
        authorNames[data.created_by] = author?.username || '同组组员'
      }
    }
  } catch (error) {
    if (token !== noteLoadToken) return
    const cached = readCachedNote(summary.id)
    if (cached) {
      activeNote.value = { ...summary, ...cached }
      activeNoteId.value = cached.id
      draft.title = cached.title
      draft.content = cached.content || ''
      dirty.value = false
      saveState.value = online.value ? 'saved' : 'offline'
      lastSavedAt.value = cached.updated_at
      activeFolderId.value = cached.folder_id || ''
      toast.info('无法连接服务器，已从本地缓存打开这篇笔记')
    } else {
      activeNote.value = null
      activeNoteId.value = ''
      toast.error(errorMessage(error, '笔记打开失败'))
    }
  } finally {
    if (token === noteLoadToken) noteLoading.value = false
    sidebarOpen.value = false
  }
}

function markDirty() {
  if (readOnly.value || !activeNote.value) return
  dirty.value = true
  dirtyVersion += 1
  saveState.value = online.value ? 'dirty' : 'offline'
  cacheDraft()
  scheduleSave()
}

function cacheDraft() {
  if (!activeNote.value) return
  cacheNote({
    ...activeNote.value,
    title: draft.title,
    content: draft.content,
    cached_at: new Date().toISOString()
  })
}

function scheduleSave(delay = 850) {
  if (saveTimer) clearTimeout(saveTimer)
  saveTimer = window.setTimeout(() => {
    saveTimer = null
    saveNow()
  }, delay)
}

function updateTitle(value) {
  draft.title = value
  markDirty()
}

function updateContent(value) {
  draft.content = value
  markDirty()
}

function onTitleBlur() {
  if (!draft.title.trim() && activeNote.value) {
    draft.title = '未命名笔记'
    markDirty()
  }
  saveNow()
}

async function saveNow() {
  if (saveTimer) {
    clearTimeout(saveTimer)
    saveTimer = null
  }
  if (!activeNote.value || readOnly.value || !dirty.value) return
  if (!online.value) {
    saveState.value = 'offline'
    cacheDraft()
    return
  }
  if (savingPromise) {
    await savingPromise.catch(() => {})
    if (!activeNote.value || !dirty.value) return
  }

  const noteId = activeNote.value.id
  const version = dirtyVersion
  const title = (draft.title.trim() || '未命名笔记').slice(0, 200)
  const content = draft.content
  saveState.value = 'saving'

  const task = (async () => {
    const { data, error } = await supabase
      .from('notes')
      .update({ title, content })
      .eq('id', noteId)
      .select('id, title, content, updated_at')
      .maybeSingle()
    if (error) throw error
    if (!data) throw new Error('笔记不存在或没有编辑权限')

    const index = notes.value.findIndex((note) => note.id === noteId)
    if (index >= 0) {
      notes.value[index] = {
        ...notes.value[index],
        title: data.title,
        updated_at: data.updated_at
      }
      persistDirectoryCache()
    }

    if (activeNote.value?.id === noteId) {
      activeNote.value = { ...activeNote.value, ...data }
      lastSavedAt.value = data.updated_at
      if (dirtyVersion === version) {
        dirty.value = false
        saveState.value = 'saved'
        cacheNote({ ...activeNote.value, title: data.title, content: data.content })
      } else {
        saveState.value = 'dirty'
        cacheDraft()
      }
    } else {
      cacheNote({
        ...notes.value.find((note) => note.id === noteId),
        id: noteId,
        title: data.title,
        content: data.content,
        updated_at: data.updated_at
      })
    }
  })()
    .catch((error) => {
      if (activeNote.value?.id === noteId) {
        saveState.value = online.value ? 'error' : 'offline'
        cacheDraft()
      }
      const now = Date.now()
      if (now - lastSaveToastAt > 10000) {
        lastSaveToastAt = now
        toast.error(
          navigator.onLine
            ? errorMessage(error, '自动保存失败，内容已缓存到本地')
            : '当前离线，内容已缓存到本地'
        )
      }
    })
    .finally(() => {
      if (savingPromise === task) savingPromise = null
    })

  savingPromise = task
  await task

  if (activeNote.value?.id === noteId && dirty.value && saveState.value !== 'error' && online.value) {
    scheduleSave(500)
  }
}

async function createNote(folderId) {
  if (!activeGroup.value) return
  await saveNow()
  sidebarOpen.value = false
  try {
    const { data, error } = await supabase
      .from('notes')
      .insert({
        group_id: activeGroup.value.id,
        folder_id: folderId || null,
        title: '未命名笔记',
        content: ''
      })
      .select('*')
      .single()
    if (error) throw error

    notes.value = [data, ...notes.value]
    persistDirectoryCache()
    activeFolderId.value = data.folder_id || ''
    activeNote.value = data
    activeNoteId.value = data.id
    draft.title = data.title
    draft.content = data.content || ''
    dirty.value = false
    dirtyVersion += 1
    saveState.value = 'saved'
    lastSavedAt.value = data.updated_at
    cacheNote(data)
    expandAncestors(data.folder_id)
    try {
      localStorage.setItem(storageKey('activeNote'), data.id)
    } catch {
      // ignore
    }
  } catch (error) {
    toast.error(errorMessage(error, '新建笔记失败'))
  }
}

async function deleteNote() {
  if (!activeNote.value) return
  if (!window.confirm(`删除笔记「${draft.title || '未命名笔记'}」？此操作不可恢复。`)) return
  if (saveTimer) {
    clearTimeout(saveTimer)
    saveTimer = null
  }
  const noteId = activeNote.value.id
  try {
    const { error } = await supabase.from('notes').delete().eq('id', noteId)
    if (error) throw error
    notes.value = notes.value.filter((note) => note.id !== noteId)
    persistDirectoryCache()
    removeCachedNote(noteId)
    resetNoteState()
    toast.success('笔记已删除')
  } catch (error) {
    toast.error(errorMessage(error, '删除失败'))
  }
}

function exportNote() {
  if (!activeNote.value) return
  downloadMarkdown(draft.title, draft.content)
  toast.success('Markdown 文件已导出')
}

function openCreateFolder(parentId) {
  if (!activeGroup.value) return
  folderDialog.open = true
  folderDialog.mode = 'create'
  folderDialog.parentId = parentId || null
  folderDialog.folder = null
  folderDialog.name = ''
  folderDialog.busy = false
}

function openRenameFolder(folder) {
  folderDialog.open = true
  folderDialog.mode = 'rename'
  folderDialog.parentId = folder.parent_id || null
  folderDialog.folder = folder
  folderDialog.name = folder.name
  folderDialog.busy = false
}

async function submitFolder() {
  if (!activeGroup.value) return
  const name = folderDialog.name.trim()
  if (!name) {
    toast.error('文件夹名称不能为空')
    return
  }
  if (name.length > 80) {
    toast.error('文件夹名称不能超过 80 个字符')
    return
  }
  folderDialog.busy = true
  try {
    if (folderDialog.mode === 'rename' && folderDialog.folder) {
      const { data, error } = await supabase
        .from('folders')
        .update({ name })
        .eq('id', folderDialog.folder.id)
        .select('id, group_id, parent_id, name, created_by, created_at, updated_at')
        .single()
      if (error) throw error
      const index = folders.value.findIndex((folder) => folder.id === data.id)
      if (index >= 0) folders.value[index] = data
      persistDirectoryCache()
      toast.success('文件夹已重命名')
    } else {
      const { data, error } = await supabase
        .from('folders')
        .insert({
          group_id: activeGroup.value.id,
          parent_id: folderDialog.parentId || null,
          name
        })
        .select('id, group_id, parent_id, name, created_by, created_at, updated_at')
        .single()
      if (error) throw error
      folders.value = [...folders.value, data]
      persistDirectoryCache()
      if (data.parent_id) expandAncestors(data.parent_id)
      toast.success('文件夹已创建')
    }
    folderDialog.open = false
  } catch (error) {
    toast.error(errorMessage(error, '文件夹保存失败'))
  } finally {
    folderDialog.busy = false
  }
}

async function deleteFolder(folder) {
  if (!folder) return
  const message = `删除文件夹「${folder.name}」？\n\n子文件夹会一并删除，其中的笔记会移动到群组根目录（不会删除笔记）。`
  if (!window.confirm(message)) return
  await saveNow()
  try {
    const { error } = await supabase.from('folders').delete().eq('id', folder.id)
    if (error) throw error
    toast.success('文件夹已删除，笔记已移动到根目录')
    await loadData(activeGroupId.value, { preserveActive: true })
  } catch (error) {
    toast.error(errorMessage(error, '文件夹删除失败'))
  }
}

async function refreshDirectory() {
  if (!activeGroup.value) return
  if (loadingData.value || noteLoading.value) return
  await saveNow()
  await loadData(activeGroupId.value, { preserveActive: Boolean(activeNoteId.value) })
  toast.success('目录已刷新')
}

async function selectGroup(id) {
  if (!id || id === activeGroupId.value) {
    sidebarOpen.value = false
    return
  }
  await saveNow()
  setActiveGroup(id)
  sidebarOpen.value = false
  await loadData(id)
}

function openCreateGroup() {
  createGroupOpen.value = true
  createGroupName.value = ''
  createGroupBusy.value = false
}

async function createGroup() {
  const name = createGroupName.value.trim()
  if (!name) {
    toast.error('请填写群组名称')
    return
  }
  createGroupBusy.value = true
  try {
    const { data: groupId, error } = await supabase.rpc('ln_create_group', { p_name: name })
    if (error) throw error
    await reloadGroups(groupId)
    setActiveGroup(groupId)
    createGroupOpen.value = false
    await loadData(groupId)
    toast.success('群组已创建')
  } catch (error) {
    toast.error(errorMessage(error, '创建群组失败'))
  } finally {
    createGroupBusy.value = false
  }
}

function openJoinGroup(code = '') {
  joinInitialCode.value = (code || '').toUpperCase()
  joinDialogOpen.value = true
}

async function handleJoinedGroup(groupId) {
  await reloadGroups(groupId)
  setActiveGroup(groupId)
  await loadData(groupId)
}

function openGroupSettings(tab = 'members') {
  if (!activeGroup.value) return
  groupDialogTab.value = tab
  groupDialogOpen.value = true
}

async function handleGroupChanged() {
  try {
    await reloadGroups(activeGroupId.value)
    if (!activeGroup.value) {
      resetNoteState()
      folders.value = []
      notes.value = []
    }
  } catch (error) {
    toast.error(errorMessage(error, '群组信息刷新失败'))
  }
}

async function handleGroupLeft() {
  const wasActive = activeGroupId.value
  try {
    clearGroupCache(uid.value, wasActive)
    await reloadGroups()
    groupDialogOpen.value = false
    resetNoteState()
    folders.value = []
    notes.value = []
    if (activeGroup.value) await loadData(activeGroupId.value)
    else setActiveGroup('')
    if (wasActive) toast.info('你已退出该群组')
  } catch (error) {
    toast.error(errorMessage(error, '群组列表刷新失败'))
  }
}

function handleProfileUpdated(nextProfile) {
  profile.value = nextProfile
  cacheProfile(uid.value, nextProfile)
}

async function signOut() {
  await saveNow()
  try {
    const { error } = await supabase.auth.signOut()
    if (error) throw error
  } catch (error) {
    toast.error(errorMessage(error, '退出登录失败'))
  }
  clearUserCache(uid.value)
  emit('signed-out')
}

function handleOnline() {
  online.value = true
  toast.info('网络已恢复')
  if (activeNote.value && dirty.value) saveNow()
}

function handleOffline() {
  online.value = false
  if (dirty.value) {
    saveState.value = 'offline'
    cacheDraft()
  }
  toast.info('当前处于离线状态，笔记会先保存在本机')
}

function handleBeforeUnload(event) {
  if (dirty.value || savingPromise) {
    event.preventDefault()
    event.returnValue = ''
  }
}

function handleVisibilityChange() {
  if (document.visibilityState === 'hidden' && dirty.value) {
    cacheDraft()
    saveNow()
  }
}

onMounted(async () => {
  window.addEventListener('online', handleOnline)
  window.addEventListener('offline', handleOffline)
  window.addEventListener('beforeunload', handleBeforeUnload)
  document.addEventListener('visibilitychange', handleVisibilityChange)

  try {
    await loadProfile()

    const url = new URL(window.location.href)
    const invite = url.searchParams.get('invite')
    if (invite) {
      openJoinGroup(invite)
      url.searchParams.delete('invite')
      const clean = `${url.pathname}${url.search}${url.hash}`
      window.history.replaceState({}, '', clean || url.pathname)
    }

    await reloadGroups()
    if (activeGroup.value) {
      await loadData(activeGroupId.value)
    }
  } catch (error) {
    toast.error(errorMessage(error, '加载工作区失败，请刷新重试'))
  } finally {
    bootLoading.value = false
  }
})

onBeforeUnmount(() => {
  if (saveTimer) clearTimeout(saveTimer)
  window.removeEventListener('online', handleOnline)
  window.removeEventListener('offline', handleOffline)
  window.removeEventListener('beforeunload', handleBeforeUnload)
  document.removeEventListener('visibilitychange', handleVisibilityChange)
  if (dirty.value) saveNow()
})
</script>
