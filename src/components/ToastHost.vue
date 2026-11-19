<template>
  <Teleport to="body">
    <div class="toast-host" aria-live="polite" aria-atomic="false">
      <TransitionGroup name="toast">
        <div
          v-for="item in toasts"
          :key="item.id"
          class="toast"
          :class="`toast-${item.type}`"
        >
          <AppIcon
            :name="item.type === 'success' ? 'checkcircle' : item.type === 'error' ? 'alert-triangle' : 'info'"
            :size="17"
          />
          <span class="toast-text">{{ item.message }}</span>
          <button class="toast-close" type="button" aria-label="关闭提示" @click="toast.remove(item.id)">
            <AppIcon name="x" :size="14" />
          </button>
        </div>
      </TransitionGroup>
    </div>
  </Teleport>
</template>

<script setup>
import AppIcon from './AppIcon.vue'
import { toasts, toast } from '../lib/toast'
</script>
