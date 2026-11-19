<template>
  <aside class="sidebar" :class="{ 'mobile-open': mobileOpen }">
    <header class="sidebar-brand">
      <div class="sidebar-brand-left">
        <span class="brand-mark"><AppIcon name="leaf" :size="20" /></span>
        <div>
          <strong>轻笺</strong>
          <span>LeafNote</span>
        </div>
      </div>
      <button class="icon-btn sidebar-close" type="button" aria-label="关闭侧边栏" @click="$emit('close-mobile')">
        <AppIcon name="x" :size="19" />
      </button>
    </header>

    <div class="group-switcher" ref="groupSwitcher">
      <button
        class="group-switch-btn"
        type="button"
        :aria-expanded="groupMenuOpen"
        @click="groupMenuOpen = !groupMenuOpen"
      >
        <span class="group-avatar"><AppIcon name="users" :size="16" /></span>
        <span class="group-switch-text">
          <strong>{{ activeGroup?.name || '选择群组' }}</strong>
          <small v-if="activeGroup">{{ roleLabel }} · {{ groups.length }} 个群组</small>
          <small v-else>创建或加入一个群组开始</small>
        </span>
        <AppIcon name="chevron-down" :size="15" class="group-chevron" />
      </button>

      <Transition name="pop">
        <div v-if="groupMenuOpen" class="group-menu">
          <p class="group-menu-label">我的群组</p>
          <button
            v-for="item in groups"
            :key="item.id"
            class="group-menu-item"
            :class="{ active: item.id === activeGroup?.id }"
            type="button"
            @click="chooseGroup(item.id)"
          >
            <span class="group-dot">{{ Array.from(item.name)[0] }}</span>
            <span class="group-menu-name">{{ item.name }}</span>
            <span class="group-menu-role">{{ item.role === 'admin' ? '管理员' : '组员' }}</span>
            <AppIcon v-if="item.id === activeGroup?.id" name="check" :size="14" />
          </button>
          <p v-if="!groups.length" class="group-menu-empty">还没有群组</p>
          <div class="group-menu-actions">
            <button type="button" @click="createGroup">
              <AppIcon name="plus" :size="15" /> 新建群组
            </button>
            <button v-if="activeGroup" type="button" @click="openGroupSettings">
              <AppIcon name="settings" :size="15" /> 群组管理
            </button>
            <button type="button" @click="joinGroup">
              <AppIcon name="key" :size="15" /> 使用邀请码
            </button>
          </div>
        </div>
      </Transition>
    </div>

    <div class="sidebar-tree-head">
      <span>笔记目录</span>
      <span class="tree-head-actions">
        <button
          class="icon-btn sm"
          type="button"
          title="刷新目录"
          :disabled="!activeGroup"
          @click="$emit('refresh')"
        >
          <AppIcon name="refresh" :size="15" />
        </button>
        <button
          class="icon-btn sm"
          type="button"
          title="新建文件夹"
          :disabled="!activeGroup"
          @click="$emit('add-folder', activeFolderId || null)"
        >
          <AppIcon name="folder" :size="15" />
        </button>
        <button
          class="icon-btn sm"
          type="button"
          title="新建笔记"
          :disabled="!activeGroup"
          @click="$emit('create-note', activeFolderId || null)"
        >
          <AppIcon name="plus" :size="16" />
        </button>
      </span>
    </div>

    <nav class="sidebar-tree" aria-label="笔记目录">
      <template v-if="activeGroup">
        <button
          class="tree-row root-row"
          :class="{ selected: !activeFolderId }"
          type="button"
          @click="$emit('select-folder', '')"
        >
          <span class="tree-toggle-spacer"></span>
          <AppIcon name="home" :size="15" />
          <span class="tree-text">群组根目录</span>
          <span class="tree-count">{{ totalNotes }}</span>
        </button>

        <div v-if="tree.roots.length || tree.rootNotes.length" class="tree-scroll">
          <FolderTree
            :nodes="tree.roots"
            :root-notes="tree.rootNotes"
            :expanded="expanded"
            :active-note-id="activeNoteId"
            :active-folder-id="activeFolderId"
            :current-user-id="currentUserId"
            :is-admin="isAdmin"
            @toggle="$emit('toggle-folder', $event)"
            @select-folder="$emit('select-folder', $event)"
            @select-note="$emit('select-note', $event)"
            @create-note="$emit('create-note', $event)"
            @add-folder="$emit('add-folder', $event)"
            @rename-folder="$emit('rename-folder', $event)"
            @delete-folder="$emit('delete-folder', $event)"
          />
        </div>
        <div v-else class="sidebar-empty">
          <span class="sidebar-empty-icon"><AppIcon name="folder" :size="24" /></span>
          <strong>目录还是空的</strong>
          <p>先新建一条笔记，或创建文件夹整理思路。</p>
          <button class="btn btn-primary btn-sm" type="button" @click="$emit('create-note', activeFolderId || null)">
            <AppIcon name="plus" :size="15" /> 新建笔记
          </button>
        </div>
      </template>

      <div v-else class="sidebar-empty no-group">
        <span class="sidebar-empty-icon"><AppIcon name="users" :size="24" /></span>
        <strong>还没有加入群组</strong>
        <p>每个人都可以创建无限多个群组。创建一个，或使用邀请码加入。</p>
        <button class="btn btn-primary btn-sm" type="button" @click="createGroup">
          <AppIcon name="plus" :size="15" /> 新建群组
        </button>
      </div>
    </nav>

    <footer class="sidebar-footer">
      <button class="account-button" type="button" title="个人资料" @click="$emit('open-profile')">
        <UserAvatar :profile="profile" :size="36" />
        <span class="account-text">
          <strong>{{ profile?.username || '加载中…' }}</strong>
          <small><AppIcon name="shield" :size="12" /> 隐私优先</small>
        </span>
        <AppIcon name="settings" :size="15" class="account-gear" />
      </button>
      <button class="icon-btn signout-btn" type="button" title="退出登录" aria-label="退出登录" @click="signOut">
        <AppIcon name="log-out" :size="17" />
      </button>
    </footer>
  </aside>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import AppIcon from './AppIcon.vue'
import FolderTree from './FolderTree.vue'
import UserAvatar from './UserAvatar.vue'

const props = defineProps({
  profile: { type: Object, default: null },
  groups: { type: Array, default: () => [] },
  activeGroup: { type: Object, default: null },
  groupRole: { type: String, default: 'member' },
  tree: { type: Object, default: () => ({ roots: [], rootNotes: [] }) },
  expanded: { type: Set, default: () => new Set() },
  activeNoteId: { type: String, default: '' },
  activeFolderId: { type: String, default: '' },
  currentUserId: { type: String, default: '' },
  mobileOpen: { type: Boolean, default: false }
})
const emit = defineEmits([
  'close-mobile',
  'select-group',
  'create-group',
  'join-group',
  'open-group-settings',
  'open-profile',
  'sign-out',
  'refresh',
  'toggle-folder',
  'select-folder',
  'select-note',
  'create-note',
  'add-folder',
  'rename-folder',
  'delete-folder'
])

const groupMenuOpen = ref(false)
const groupSwitcher = ref(null)

const isAdmin = computed(() => props.groupRole === 'admin')
const roleLabel = computed(() => (isAdmin.value ? '管理员' : '普通组员'))
const totalNotes = computed(() => props.tree.notesCount || 0)

function closeMenuOnOutside(event) {
  if (groupMenuOpen.value && groupSwitcher.value && !groupSwitcher.value.contains(event.target)) {
    groupMenuOpen.value = false
  }
}

onMounted(() => document.addEventListener('pointerdown', closeMenuOnOutside))
onBeforeUnmount(() => document.removeEventListener('pointerdown', closeMenuOnOutside))

function chooseGroup(id) {
  groupMenuOpen.value = false
  if (id !== props.activeGroup?.id) emit('select-group', id)
}

function createGroup() {
  groupMenuOpen.value = false
  emit('create-group')
}

function openGroupSettings() {
  groupMenuOpen.value = false
  emit('open-group-settings')
}

function joinGroup() {
  groupMenuOpen.value = false
  emit('join-group')
}

function signOut() {
  if (window.confirm('确定退出登录吗？未保存的更改会丢失。')) emit('sign-out')
}
</script>
