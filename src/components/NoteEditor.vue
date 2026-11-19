<template>
  <section class="note-editor">
    <header class="note-topbar">
      <button class="icon-btn mobile-menu-btn" type="button" aria-label="打开目录" @click="$emit('open-sidebar')">
        <AppIcon name="menu" :size="19" />
      </button>

      <div class="note-heading">
        <input
          class="note-title-input"
          :value="draft.title"
          type="text"
          maxlength="200"
          placeholder="未命名笔记"
          :readonly="readOnly"
          aria-label="笔记标题"
          @input="$emit('update-title', $event.target.value)"
          @blur="$emit('title-blur')"
          @keydown.enter.prevent="$event.target.blur()"
        />
        <div class="note-meta">
          <span class="save-status" :class="`save-${saveState}`">
            <span class="save-dot"></span>
            {{ saveLabel }}
          </span>
          <span class="meta-divider"></span>
          <span>{{ authorName || '未知作者' }}</span>
          <span class="meta-divider"></span>
          <span>{{ draft.content.length }} 字符</span>
        </div>
      </div>

      <div class="note-actions">
        <button class="btn btn-ghost btn-sm export-btn" type="button" title="导出为 Markdown" @click="$emit('export')">
          <AppIcon name="download" :size="16" />
          <span>导出</span>
        </button>
        <button
          v-if="!readOnly"
          class="icon-btn danger-hover"
          type="button"
          title="删除笔记"
          @click="$emit('delete')"
        >
          <AppIcon name="trash" :size="17" />
        </button>
      </div>
    </header>

    <div v-if="readOnly" class="readonly-banner">
      <AppIcon name="eye" :size="16" />
      <span>只读模式 · 由 <strong>{{ authorName }}</strong> 创建。只有作者能编辑笔记和运行其中的脚本。</span>
    </div>

    <div class="editor-bar">
      <div class="view-toggle desktop-view-toggle" role="group" aria-label="视图模式">
        <button type="button" :class="{ active: viewMode === 'edit' }" @click="setView('edit')">编辑</button>
        <button type="button" :class="{ active: viewMode === 'split' }" @click="setView('split')">分屏</button>
        <button type="button" :class="{ active: viewMode === 'preview' }" @click="setView('preview')">预览</button>
      </div>

      <div class="view-toggle mobile-view-toggle" role="group" aria-label="视图模式">
        <button type="button" :class="{ active: mobilePane === 'edit' }" @click="mobilePane = 'edit'">编辑</button>
        <button type="button" :class="{ active: mobilePane === 'preview' }" @click="mobilePane = 'preview'">预览</button>
      </div>

      <div v-if="!readOnly" class="format-tools" role="toolbar" aria-label="Markdown 格式工具">
        <button type="button" title="加粗 (Ctrl/Cmd+B)" @click="wrap('**', '**', '加粗文字')"><strong>B</strong></button>
        <button type="button" title="斜体 (Ctrl/Cmd+I)" @click="wrap('*', '*', '斜体文字')"><em>I</em></button>
        <button type="button" title="二级标题" @click="insertAtLineStart('## ', '标题')">H2</button>
        <button type="button" title="链接" @click="wrap('[', '](https://)', '链接文字')">链接</button>
        <button type="button" title="行内代码" @click="wrap('`', '`', '代码')">&lt;/&gt;</button>
        <button type="button" title="表格" @click="insertBlock(TABLE_SNIPPET)">表格</button>
        <button type="button" title="公式" @click="insertBlock(MATH_SNIPPET)">公式</button>
        <button type="button" title="代码块" @click="insertBlock(CODE_SNIPPET)">代码</button>
        <button type="button" class="script-tool" title="插入自定义脚本块（仅作者可运行）" @click="insertBlock(SCRIPT_SNIPPET)">
          脚本
        </button>
      </div>
      <span v-else class="readonly-spacer"></span>
    </div>

    <div class="editor-split" :class="splitClass">
      <div class="editor-pane">
        <textarea
          ref="textarea"
          class="markdown-textarea"
          :value="draft.content"
          :readonly="readOnly"
          spellcheck="false"
          placeholder="开始写点什么…&#10;&#10;支持 Markdown：## 标题、**加粗**、表格、代码块、$公式$。&#10;在代码块语言处填写 script 可插入自定义脚本。"
          aria-label="Markdown 编辑器"
          @input="$emit('update-content', $event.target.value)"
          @keydown="onKeydown"
        ></textarea>
      </div>
      <div class="preview-pane">
        <div class="preview-pane-head">
          <span>预览</span>
          <span class="preview-hint">KaTeX · GFM</span>
        </div>
        <MarkdownPreview
          :key="noteId"
          :content="draft.content"
          :can-run-scripts="currentUserId === note?.created_by"
          :note-id="noteId"
          :note-title="draft.title"
        />
      </div>
    </div>
  </section>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import AppIcon from './AppIcon.vue'
import MarkdownPreview from './MarkdownPreview.vue'

const props = defineProps({
  note: { type: Object, default: null },
  draft: { type: Object, required: true },
  noteId: { type: String, default: '' },
  authorName: { type: String, default: '' },
  currentUserId: { type: String, default: '' },
  readOnly: { type: Boolean, default: false },
  saveState: { type: String, default: 'saved' },
  lastSavedAt: { type: String, default: '' }
})
const emit = defineEmits([
  'update-title',
  'update-content',
  'title-blur',
  'export',
  'delete',
  'open-sidebar'
])

const TABLE_SNIPPET = `| 列 1 | 列 2 |\n| --- | --- |\n| 内容 | 内容 |\n`
const MATH_SNIPPET = `$$\nE = mc^2\n$$\n`
const CODE_SNIPPET = '```js\nconsole.log(\"Hello LeafNote\")\n```\n'
const SCRIPT_SNIPPET = `\`\`\`script
// 该脚本只会在作者本人查看此笔记时运行。
// 运行环境为 sandbox="allow-scripts" 的 iframe，无法访问本站数据。
const box = document.createElement('div')
box.textContent = 'Hello from custom script · ' + new Date().toLocaleTimeString()
document.body.appendChild(box)
\`\`\`\n`

const textarea = ref(null)
const savedMode = localStorage.getItem('leafnote.viewMode')
const viewMode = ref(['split', 'edit', 'preview'].includes(savedMode) ? savedMode : 'split')
const mobilePane = ref('edit')
const isMobile = ref(false)
let mediaQuery = null

const saveLabel = computed(() => {
  const labels = {
    saved: '已保存',
    saving: '保存中…',
    dirty: '待保存',
    offline: '离线 · 已缓存',
    error: '保存失败'
  }
  return labels[props.saveState] || '已保存'
})

const splitClass = computed(() => {
  if (isMobile.value) return `mobile-${mobilePane.value}`
  return `view-${viewMode.value}`
})

function setView(mode) {
  viewMode.value = mode
  localStorage.setItem('leafnote.viewMode', mode)
}

function updateMedia() {
  isMobile.value = window.matchMedia('(max-width: 860px)').matches
}

onMounted(() => {
  mediaQuery = window.matchMedia('(max-width: 860px)')
  isMobile.value = mediaQuery.matches
  mediaQuery.addEventListener?.('change', updateMedia)
})
onBeforeUnmount(() => mediaQuery?.removeEventListener?.('change', updateMedia))

function insertBlock(text) {
  if (props.readOnly) return
  const el = textarea.value
  if (!el) return
  const start = el.selectionStart ?? props.draft.content.length
  const end = el.selectionEnd ?? start
  const before = props.draft.content.slice(0, start)
  const prefix = before && !before.endsWith('\n\n') ? (before.endsWith('\n') ? '\n' : '\n\n') : ''
  const next = before + prefix + text + props.draft.content.slice(end)
  emitContent(next)
  nextTick(() => {
    el.focus()
    const cursor = start + prefix.length + text.length
    el.setSelectionRange(cursor, cursor)
  })
}

function wrap(before, after, placeholder) {
  if (props.readOnly) return
  const el = textarea.value
  if (!el) return
  const start = el.selectionStart ?? 0
  const end = el.selectionEnd ?? start
  const selected = props.draft.content.slice(start, end) || placeholder
  const next =
    props.draft.content.slice(0, start) +
    before +
    selected +
    after +
    props.draft.content.slice(end)
  emitContent(next)
  nextTick(() => {
    el.focus()
    el.setSelectionRange(start + before.length, start + before.length + selected.length)
  })
}

function insertAtLineStart(prefix, placeholder) {
  if (props.readOnly) return
  const el = textarea.value
  if (!el) return
  const start = el.selectionStart ?? 0
  const lineStart = props.draft.content.lastIndexOf('\n', start - 1) + 1
  const selected = props.draft.content.slice(start, el.selectionEnd ?? start) || placeholder
  const next =
    props.draft.content.slice(0, lineStart) +
    prefix +
    selected +
    props.draft.content.slice(el.selectionEnd ?? start)
  emitContent(next)
  nextTick(() => {
    el.focus()
    el.setSelectionRange(lineStart + prefix.length, lineStart + prefix.length + selected.length)
  })
}

function emitContent(value) {
  emit('update-content', value)
}

function onKeydown(event) {
  if (props.readOnly) return
  const meta = event.metaKey || event.ctrlKey
  if (meta && event.key.toLowerCase() === 'b') {
    event.preventDefault()
    wrap('**', '**', '加粗文字')
    return
  }
  if (meta && event.key.toLowerCase() === 'i') {
    event.preventDefault()
    wrap('*', '*', '斜体文字')
    return
  }
  if (event.key === 'Tab') {
    event.preventDefault()
    const el = textarea.value
    const start = el.selectionStart ?? 0
    const end = el.selectionEnd ?? start
    const next = `${props.draft.content.slice(0, start)}  ${props.draft.content.slice(end)}`
    emitContent(next)
    nextTick(() => el.setSelectionRange(start + 2, start + 2))
  }
}
</script>
