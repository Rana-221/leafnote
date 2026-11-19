<template>
  <ul class="tree-list">
    <li v-for="folder in nodes" :key="folder.id" class="tree-folder">
      <div
        class="tree-row folder-row"
        :class="{ selected: activeFolderId === folder.id }"
        :style="{ '--depth': depth }"
      >
        <button
          v-if="hasChildren(folder)"
          class="tree-toggle"
          type="button"
          :aria-label="expanded.has(folder.id) ? '折叠文件夹' : '展开文件夹'"
          :aria-expanded="expanded.has(folder.id)"
          @click.stop="$emit('toggle', folder.id)"
        >
          <AppIcon :name="expanded.has(folder.id) ? 'chevron-down' : 'chevron-right'" :size="14" />
        </button>
        <span v-else class="tree-toggle-spacer"></span>

        <button
          class="tree-label folder-label"
          type="button"
          :title="folder.name"
          @click="$emit('select-folder', folder.id)"
        >
          <AppIcon :name="expanded.has(folder.id) ? 'folder-open' : 'folder'" :size="16" />
          <span class="tree-text">{{ folder.name }}</span>
          <span v-if="countNotes(folder)" class="tree-count">{{ countNotes(folder) }}</span>
        </button>

        <span class="tree-actions">
          <button class="tree-action" type="button" title="在此文件夹新建笔记" @click.stop="$emit('create-note', folder.id)">
            <AppIcon name="plus" :size="14" />
          </button>
          <button class="tree-action" type="button" title="新建子文件夹" @click.stop="$emit('add-folder', folder.id)">
            <AppIcon name="folder" :size="14" />
          </button>
          <button
            v-if="canManage(folder)"
            class="tree-action"
            type="button"
            title="重命名文件夹"
            @click.stop="$emit('rename-folder', folder)"
          >
            <AppIcon name="pencil" :size="13" />
          </button>
          <button
            v-if="canManage(folder)"
            class="tree-action danger-hover"
            type="button"
            title="删除文件夹"
            @click.stop="$emit('delete-folder', folder)"
          >
            <AppIcon name="trash" :size="13" />
          </button>
        </span>
      </div>

      <template v-if="expanded.has(folder.id)">
        <FolderTree
          v-if="folder.children.length"
          :nodes="folder.children"
          :root-notes="[]"
          :expanded="expanded"
          :active-note-id="activeNoteId"
          :active-folder-id="activeFolderId"
          :current-user-id="currentUserId"
          :is-admin="isAdmin"
          :depth="depth + 1"
          @toggle="$emit('toggle', $event)"
          @select-folder="$emit('select-folder', $event)"
          @select-note="$emit('select-note', $event)"
          @create-note="$emit('create-note', $event)"
          @add-folder="$emit('add-folder', $event)"
          @rename-folder="$emit('rename-folder', $event)"
          @delete-folder="$emit('delete-folder', $event)"
        />

        <li v-for="note in folder.notes" :key="note.id" class="tree-note-item">
          <button
            class="tree-row note-row"
            :class="{ selected: activeNoteId === note.id }"
            :style="{ '--depth': depth + 1 }"
            type="button"
            :title="note.title"
            @click="$emit('select-note', note)"
          >
            <span class="tree-toggle-spacer"></span>
            <AppIcon name="note" :size="15" class="note-icon" />
            <span class="tree-text">{{ note.title || '未命名笔记' }}</span>
          </button>
        </li>

        <li v-if="!folder.children.length && !folder.notes.length" class="tree-empty-folder">
          <span :style="{ paddingLeft: `${(depth + 1) * 14 + 18}px` }">空文件夹</span>
        </li>
      </template>
    </li>

    <li v-for="note in rootNotes" :key="note.id" class="tree-note-item">
      <button
        class="tree-row note-row"
        :class="{ selected: activeNoteId === note.id }"
        :style="{ '--depth': depth }"
        type="button"
        :title="note.title"
        @click="$emit('select-note', note)"
      >
        <span class="tree-toggle-spacer"></span>
        <AppIcon name="note" :size="15" class="note-icon" />
        <span class="tree-text">{{ note.title || '未命名笔记' }}</span>
      </button>
    </li>
  </ul>
</template>

<script setup>
import AppIcon from './AppIcon.vue'
import { countTreeNotes } from '../lib/tree'

defineOptions({ name: 'FolderTree' })

const props = defineProps({
  nodes: { type: Array, default: () => [] },
  rootNotes: { type: Array, default: () => [] },
  expanded: { type: Set, default: () => new Set() },
  activeNoteId: { type: String, default: '' },
  activeFolderId: { type: String, default: '' },
  currentUserId: { type: String, default: '' },
  isAdmin: { type: Boolean, default: false },
  depth: { type: Number, default: 0 }
})

defineEmits([
  'toggle',
  'select-folder',
  'select-note',
  'create-note',
  'add-folder',
  'rename-folder',
  'delete-folder'
])

function hasChildren(folder) {
  return folder.children.length > 0 || folder.notes.length > 0
}

function countNotes(folder) {
  return countTreeNotes(folder)
}

function canManage(folder) {
  return folder.created_by === props.currentUserId || props.isAdmin
}
</script>
