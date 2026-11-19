<template>
  <div ref="host" class="markdown-preview">
    <div v-if="!content.trim()" class="preview-empty">
      <AppIcon name="leaf" :size="28" />
      <p>预览会随着输入实时更新</p>
      <span>支持表格、代码高亮、KaTeX 公式与自定义脚本块</span>
    </div>
    <article v-else class="markdown-body" v-html="rendered.html"></article>
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import AppIcon from './AppIcon.vue'
import { clampScriptFrameHeight, hydrateScriptBlocks, renderMarkdown } from '../lib/markdown'

const props = defineProps({
  content: { type: String, default: '' },
  canRunScripts: { type: Boolean, default: false },
  noteId: { type: String, default: '' },
  noteTitle: { type: String, default: '' }
})

const host = ref(null)
const rendered = computed(() => renderMarkdown(props.content))

function hydrate() {
  hydrateScriptBlocks(host.value, rendered.value.scripts, {
    canRunScripts: props.canRunScripts,
    noteId: props.noteId,
    noteTitle: props.noteTitle
  })
}

watch(
  rendered,
  async () => {
    await nextTick()
    hydrate()
  },
  { flush: 'post' }
)

watch(
  () => props.canRunScripts,
  async () => {
    await nextTick()
    hydrate()
  }
)

function onMessage(event) {
  if (!host.value) return
  const frames = host.value.querySelectorAll('.script-frame')
  for (const frame of frames) {
    if (event.source === frame.contentWindow) {
      const height = clampScriptFrameHeight(event.data?.height)
      if (height) frame.style.height = `${height}px`
      break
    }
  }
}

onMounted(() => {
  window.addEventListener('message', onMessage)
  hydrate()
})
onBeforeUnmount(() => window.removeEventListener('message', onMessage))
</script>
