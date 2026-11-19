<template>
  <ModalDialog
    :open="open"
    title="个人资料"
    subtitle="管理头像、用户名、实名信息与手机号绑定"
    size="md"
    @close="$emit('close')"
  >
    <form id="profile-form" class="profile-form" @submit.prevent="save">
      <div v-if="loading" class="dialog-loading">
        <AppIcon name="loader" :size="20" class="spin" /> 正在读取资料…
      </div>

      <template v-else>
        <section class="profile-account">
          <div class="avatar-editor">
            <img v-if="filePreview" :src="filePreview" alt="新头像预览" />
            <UserAvatar v-else :profile="{ ...profile, avatar_path: avatarPath }" :size="76" />
            <button class="avatar-camera" type="button" title="上传新头像" @click="fileInput?.click()">
              <AppIcon name="camera" :size="16" />
            </button>
          </div>
          <div class="profile-account-main">
            <strong>{{ profile?.username }}</strong>
            <span>{{ session.user.email }}</span>
            <div class="profile-account-actions">
              <button class="text-link" type="button" @click="fileInput?.click()">
                {{ avatarPath ? '更换头像' : '上传头像' }}
              </button>
              <button v-if="file" class="text-link danger-text" type="button" @click="clearSelectedFile">
                取消选择
              </button>
            </div>
            <p class="field-hint">JPG / PNG / WebP，会自动压缩为 512px；头像仅同组组员可读取。</p>
          </div>
          <input
            ref="fileInput"
            type="file"
            accept="image/jpeg,image/png,image/webp"
            class="sr-only"
            @change="onFileChange"
          />
        </section>

        <section class="form-section">
          <h3>公开资料</h3>
          <label class="field">
            <span>用户名</span>
            <input v-model="username" type="text" maxlength="24" required />
            <small class="field-hint">2–24 个字符。用户名会显示给与你同组的成员。</small>
          </label>
          <label class="field">
            <span>邮箱</span>
            <input :value="session.user.email" type="email" disabled />
            <small class="field-hint inline-hint">
              <AppIcon name="checkcircle" :size="14" />
              已通过邮箱验证
            </small>
          </label>
        </section>

        <section class="form-section">
          <div class="section-title-row">
            <h3>实名信息</h3>
            <span class="privacy-chip"><AppIcon name="shield" :size="13" /> 仅组内可见</span>
          </div>
          <p class="section-description">
            组外用户无法读取实名数据。群组管理员可在群组设置中调整组内可见范围。
          </p>
          <div class="form-grid">
            <label class="field">
              <span>真实姓名</span>
              <input v-model="realName" type="text" maxlength="80" autocomplete="name" placeholder="选填" />
            </label>
            <label class="field">
              <span>证件号码</span>
              <input v-model="idNumber" type="text" maxlength="64" autocomplete="off" placeholder="选填" />
            </label>
          </div>
          <p class="field-hint">
            填写后将保存在独立表中，仅同组组员按群组设置读取；不属于「公开资料」。清空两项可删除实名信息。
          </p>
        </section>

        <section class="form-section">
          <div class="section-title-row">
            <h3>手机号绑定</h3>
            <span class="optional-chip">可选</span>
          </div>
          <p class="section-description">
            手机号仅用于账号验证，不向群组成员展示。需要你的 Supabase 项目已配置 Phone Provider 与短信服务。
          </p>

          <div v-if="currentPhone" class="phone-current">
            <AppIcon name="phone" :size="16" />
            <span>已绑定 {{ maskPhone(currentPhone) }}</span>
            <span class="status-dot">已验证</span>
          </div>

          <div class="phone-row">
            <label class="field">
              <span>{{ currentPhone ? '更换手机号' : '手机号' }}</span>
              <input
                v-model="phoneInput"
                type="tel"
                inputmode="tel"
                autocomplete="tel"
                placeholder="+8613800138000"
                @input="phoneStep = 'idle'"
              />
            </label>
            <button
              class="btn btn-secondary phone-send"
              type="button"
              :disabled="phoneBusy || phoneStep === 'verify'"
              @click="sendPhoneCode"
            >
              {{ phoneBusy ? '发送中…' : phoneStep === 'verify' ? '验证码已发送' : '发送验证码' }}
            </button>
          </div>

          <div v-if="phoneStep === 'verify'" class="phone-verify">
            <label class="field">
              <span>短信验证码</span>
              <input v-model="phoneCode" type="text" inputmode="numeric" maxlength="8" placeholder="输入 6 位验证码" />
            </label>
            <button class="btn btn-primary" type="button" :disabled="phoneBusy" @click="verifyPhone">
              {{ phoneBusy ? '验证中…' : '确认绑定' }}
            </button>
          </div>
          <p v-if="phoneError" class="field-error">{{ phoneError }}</p>
          <p class="field-hint">使用国际格式，例如中国大陆手机号填写 +8613800138000。未配置短信服务时可跳过。</p>
        </section>
      </template>
    </form>

    <template #footer>
      <button class="btn btn-ghost" type="button" @click="$emit('close')">取消</button>
      <button class="btn btn-primary" type="submit" form="profile-form" :disabled="saving || loading">
        <AppIcon v-if="saving" name="loader" :size="16" class="spin" />
        {{ saving ? '保存中…' : '保存资料' }}
      </button>
    </template>
  </ModalDialog>
</template>

<script setup>
import { onBeforeUnmount, ref, watch } from 'vue'
import AppIcon from './AppIcon.vue'
import ModalDialog from './ModalDialog.vue'
import UserAvatar from './UserAvatar.vue'
import { supabase } from '../lib/supabase'
import { errorMessage, isUsernameValid } from '../lib/utils'
import { uploadAvatar, deleteAvatar } from '../lib/upload'
import { invalidateAvatar } from '../lib/avatar'
import { toast } from '../lib/toast'

const props = defineProps({
  open: { type: Boolean, default: false },
  session: { type: Object, required: true },
  profile: { type: Object, default: null }
})
const emit = defineEmits(['close', 'updated'])

const loading = ref(false)
const saving = ref(false)
const username = ref('')
const avatarPath = ref('')
const realName = ref('')
const idNumber = ref('')
const fileInput = ref(null)
const file = ref(null)
const filePreview = ref('')

const currentPhone = ref('')
const phoneInput = ref('')
const phoneCode = ref('')
const phoneStep = ref('idle')
const phoneBusy = ref(false)
const phoneError = ref('')

watch(
  () => props.open,
  async (open) => {
    if (!open) return
    username.value = props.profile?.username || ''
    avatarPath.value = props.profile?.avatar_path || ''
    realName.value = ''
    idNumber.value = ''
    currentPhone.value = props.session.user.phone || ''
    phoneInput.value = props.session.user.phone || ''
    phoneStep.value = 'idle'
    phoneCode.value = ''
    phoneError.value = ''
    clearSelectedFile()
    loading.value = true
    try {
      const { data, error } = await supabase
        .from('real_identities')
        .select('real_name, id_number')
        .eq('user_id', props.session.user.id)
        .maybeSingle()
      if (error) throw error
      realName.value = data?.real_name || ''
      idNumber.value = data?.id_number || ''
    } catch (error) {
      toast.error(errorMessage(error, '实名信息读取失败'))
    } finally {
      loading.value = false
    }
  }
)

function clearSelectedFile(revoke = true) {
  if (filePreview.value && revoke) URL.revokeObjectURL(filePreview.value)
  if (fileInput.value) fileInput.value.value = ''
  file.value = null
  filePreview.value = ''
}

function onFileChange(event) {
  const selected = event.target.files?.[0]
  if (!selected) return
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(selected.type)) {
    toast.error('仅支持 JPG、PNG 或 WebP 图片')
    event.target.value = ''
    return
  }
  if (selected.size > 8 * 1024 * 1024) {
    toast.error('图片不能超过 8MB')
    event.target.value = ''
    return
  }
  clearSelectedFile()
  file.value = selected
  filePreview.value = URL.createObjectURL(selected)
}

onBeforeUnmount(() => {
  if (filePreview.value) URL.revokeObjectURL(filePreview.value)
})

async function save() {
  const cleanName = username.value.trim()
  if (!isUsernameValid(cleanName)) {
    toast.error('用户名需要 2–24 个字符，且不能包含控制字符')
    return
  }
  const hasRealName = Boolean(realName.value.trim())
  const hasIdNumber = Boolean(idNumber.value.trim())
  if (hasRealName !== hasIdNumber) {
    toast.error('真实姓名和证件号码需要同时填写，或同时留空')
    return
  }

  saving.value = true
  let uploadedPath = ''
  let profileCommitted = false
  try {
    let nextAvatarPath = avatarPath.value
    if (file.value) {
      uploadedPath = await uploadAvatar(props.session.user.id, file.value)
      nextAvatarPath = uploadedPath
    }

    const previousAvatar = props.profile?.avatar_path || ''
    const { data, error } = await supabase
      .from('profiles')
      .update({ username: cleanName, avatar_path: nextAvatarPath })
      .eq('id', props.session.user.id)
      .select('id, username, avatar_path, created_at, updated_at')
      .single()
    if (error) throw error
    profileCommitted = true
    avatarPath.value = nextAvatarPath
    if (previousAvatar && previousAvatar !== nextAvatarPath) {
      invalidateAvatar(previousAvatar)
      deleteAvatar(previousAvatar).catch(() => {})
    }
    if (nextAvatarPath) invalidateAvatar(nextAvatarPath)
    clearSelectedFile()
    emit('updated', data)

    if (hasRealName) {
      const { error: identityError } = await supabase
        .from('real_identities')
        .upsert(
          {
            user_id: props.session.user.id,
            real_name: realName.value.trim(),
            id_number: idNumber.value.trim()
          },
          { onConflict: 'user_id' }
        )
      if (identityError) throw identityError
    } else {
      const { error: identityError } = await supabase
        .from('real_identities')
        .delete()
        .eq('user_id', props.session.user.id)
      if (identityError) throw identityError
    }

    toast.success('资料已保存')
    emit('close')
  } catch (error) {
    if (uploadedPath && !profileCommitted) deleteAvatar(uploadedPath).catch(() => {})
    toast.error(errorMessage(error, '保存失败，请稍后重试'))
  } finally {
    saving.value = false
  }
}

function maskPhone(phone) {
  if (!phone) return ''
  if (phone.length <= 7) return phone
  return `${phone.slice(0, 4)}****${phone.slice(-4)}`
}

function normalizePhone() {
  return phoneInput.value.replace(/[\s()-]/g, '')
}

async function sendPhoneCode() {
  phoneError.value = ''
  const phone = normalizePhone()
  if (!/^\+[1-9]\d{6,14}$/.test(phone)) {
    phoneError.value = '请输入带国际区号的手机号，例如 +8613800138000'
    return
  }
  if (phone === currentPhone.value) {
    phoneError.value = '这已经是当前绑定的手机号'
    return
  }
  phoneBusy.value = true
  try {
    const { error } = await supabase.auth.updateUser({ phone })
    if (error) throw error
    phoneInput.value = phone
    phoneStep.value = 'verify'
    toast.success('验证码已发送，请查看短信')
  } catch (error) {
    phoneError.value = errorMessage(error, '验证码发送失败')
  } finally {
    phoneBusy.value = false
  }
}

async function verifyPhone() {
  phoneError.value = ''
  const token = phoneCode.value.trim()
  if (!/^\d{6,8}$/.test(token)) {
    phoneError.value = '请输入短信中的验证码'
    return
  }
  phoneBusy.value = true
  try {
    const { data, error } = await supabase.auth.verifyOtp({
      phone: normalizePhone(),
      token,
      type: 'phone_change'
    })
    if (error) throw error
    currentPhone.value = data.user?.phone || normalizePhone()
    phoneStep.value = 'idle'
    phoneCode.value = ''
    toast.success('手机号绑定成功')
  } catch (error) {
    phoneError.value = errorMessage(error, '验证失败，请检查验证码')
  } finally {
    phoneBusy.value = false
  }
}
</script>
