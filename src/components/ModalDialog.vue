<template>
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="open"
        class="modal-backdrop"
        role="presentation"
        @mousedown.self="onBackdrop"
      >
        <section
          ref="panel"
          class="modal-panel"
          :class="`modal-${size}`"
          role="dialog"
          aria-modal="true"
          :aria-label="title"
          tabindex="-1"
        >
          <header class="modal-head">
            <div class="modal-title-wrap">
              <h2>{{ title }}</h2>
              <p v-if="subtitle">{{ subtitle }}</p>
            </div>
            <button class="icon-btn modal-close" type="button" aria-label="关闭" @click="$emit('close')">
              <AppIcon name="x" :size="19" />
            </button>
          </header>
          <div class="modal-body">
            <slot />
          </div>
          <footer v-if="$slots.footer" class="modal-footer">
            <slot name="footer" />
          </footer>
        </section>
      </div>
    </Transition>
  </Teleport>
</template>

<script setup>
import { nextTick, onBeforeUnmount, ref, watch } from 'vue'
import AppIcon from './AppIcon.vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  size: { type: String, default: 'md' },
  closeOnBackdrop: { type: Boolean, default: true }
})
const emit = defineEmits(['close'])
const panel = ref(null)
let previousOverflow = ''
let previousFocus = null

function onBackdrop() {
  if (props.closeOnBackdrop) emit('close')
}

function onKeydown(event) {
  if (event.key === 'Escape' && props.open) emit('close')
}

watch(
  () => props.open,
  async (open) => {
    if (open) {
      previousFocus = document.activeElement
      previousOverflow = document.body.style.overflow
      document.body.style.overflow = 'hidden'
      document.addEventListener('keydown', onKeydown)
      await nextTick()
      panel.value?.focus()
    } else {
      document.body.style.overflow = previousOverflow
      document.removeEventListener('keydown', onKeydown)
      if (previousFocus instanceof HTMLElement) previousFocus.focus?.()
    }
  }
)

onBeforeUnmount(() => {
  document.body.style.overflow = previousOverflow
  document.removeEventListener('keydown', onKeydown)
})
</script>
