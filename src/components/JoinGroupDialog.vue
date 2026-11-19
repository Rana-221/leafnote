<template>
  <ModalDialog
    :open="open"
    title="加入群组"
    subtitle="使用邀请码或扫描二维码打开邀请链接"
    size="sm"
    @close="$emit('close')"
  >
    <div class="join-group">
      <form class="join-code-form" @submit.prevent="previewInvite">
        <label class="field">
          <span>邀请码</span>
          <input
            v-model="code"
            type="text"
            class="invite-code-input"
            maxlength="32"
            autocomplete="off"
            autocapitalize="characters"
            spellcheck="false"
            placeholder="输入邀请码"
            @input="previewData = null; error = ''"
          />
        </label>
        <button class="btn btn-secondary" type="submit" :disabled="loading || !code.trim()">
          <AppIcon v-if="loading" name="loader" :size="16" class="spin" />
          {{ loading ? '查询中…' : '验证' }}
        </button>
      </form>

      <div v-if="error" class="alert alert-error">
        <AppIcon name="alert-triangle" :size="17" />
        <span>{{ error }}</span>
      </div>

      <div v-if="previewData && !previewData.valid" class="alert alert-warning">
        <AppIcon name="info" :size="17" />
        <span>{{ previewData.reason || '这个邀请码不可用' }}</span>
      </div>

      <div v-if="previewData?.valid" class="join-preview">
        <div class="join-preview-icon"><AppIcon name="users" :size="24" /></div>
        <p class="eyebrow">YOU ARE INVITED</p>
        <h3>{{ previewData.group_name }}</h3>
        <p class="join-preview-meta">
          {{ previewData.member_count }} 位组员 · 邀请人 {{ previewData.inviter_username || '群组成员' }}
        </p>
        <p v-if="previewData.already_member" class="join-already">
          <AppIcon name="checkcircle" :size="15" /> 你已经在这个群组里
        </p>
        <button class="btn btn-primary btn-block" type="button" :disabled="joining" @click="join">
          <AppIcon v-if="joining" name="loader" :size="16" class="spin" />
          {{ joining ? '加入中…' : previewData.already_member ? '进入群组' : '确认加入' }}
        </button>
      </div>

      <div class="info-box join-info">
        <AppIcon name="shield" :size="17" />
        <div>
          <strong>加入后会发生什么？</strong>
          <p>你将能访问该群组的笔记、文件夹与成员资料。群组之间完全隔离，退出后立即失去访问权限。</p>
        </div>
      </div>
    </div>
  </ModalDialog>
</template>

<script setup>
import { ref, watch } from 'vue'
import AppIcon from './AppIcon.vue'
import ModalDialog from './ModalDialog.vue'
import { supabase } from '../lib/supabase'
import { errorMessage } from '../lib/utils'
import { toast } from '../lib/toast'

const props = defineProps({
  open: { type: Boolean, default: false },
  initialCode: { type: String, default: '' }
})
const emit = defineEmits(['close', 'joined'])

const code = ref('')
const previewData = ref(null)
const loading = ref(false)
const joining = ref(false)
const error = ref('')

watch(
  () => props.open,
  async (open) => {
    if (!open) return
    code.value = (props.initialCode || '').toUpperCase().trim()
    previewData.value = null
    error.value = ''
    if (code.value) await previewInvite()
  }
)

async function previewInvite() {
  const value = code.value.toUpperCase().trim()
  if (!value) return
  loading.value = true
  error.value = ''
  previewData.value = null
  try {
    const { data, error: rpcError } = await supabase.rpc('ln_get_invite_preview', {
      p_code: value
    })
    if (rpcError) throw rpcError
    previewData.value = data
  } catch (rpcError) {
    error.value = errorMessage(rpcError, '邀请码查询失败')
  } finally {
    loading.value = false
  }
}

async function join() {
  joining.value = true
  error.value = ''
  try {
    const { data, error: rpcError } = await supabase.rpc('ln_join_group_by_code', {
      p_code: code.value.toUpperCase().trim()
    })
    if (rpcError) throw rpcError
    toast.success('已加入群组')
    emit('joined', data)
    emit('close')
  } catch (rpcError) {
    error.value = errorMessage(rpcError, '加入失败')
  } finally {
    joining.value = false
  }
}
</script>
