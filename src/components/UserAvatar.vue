<template>
  <span
    class="user-avatar"
    :class="{ 'has-image': showImage }"
    :style="{ width: `${size}px`, height: `${size}px`, backgroundColor: background, fontSize: `${Math.round(size * 0.4)}px` }"
    :title="profile?.username || '用户'"
  >
    <img v-if="showImage" :src="url" alt="" @error="failed = true" />
    <span v-else>{{ initial }}</span>
  </span>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { resolveAvatarUrl } from '../lib/avatar'

const props = defineProps({
  profile: { type: Object, default: () => ({}) },
  size: { type: Number, default: 36 }
})

const url = ref('')
const failed = ref(false)
let requestId = 0

const initial = computed(() => {
  const name = (props.profile?.username || '?').trim()
  return Array.from(name)[0]?.toUpperCase() || '?'
})

const background = computed(() => {
  const source = props.profile?.username || props.profile?.id || 'leaf'
  let hash = 0
  for (let i = 0; i < source.length; i += 1) {
    hash = (hash * 31 + source.charCodeAt(i)) % 360
  }
  return `hsl(${hash} 34% 86%)`
})

const showImage = computed(() => Boolean(url.value) && !failed.value)

watch(
  () => props.profile?.avatar_path,
  async (path) => {
    const current = ++requestId
    url.value = ''
    failed.value = false
    if (!path) return
    const resolved = await resolveAvatarUrl(path)
    if (current === requestId) url.value = resolved
  },
  { immediate: true }
)
</script>
