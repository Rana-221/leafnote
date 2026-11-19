<template>
  <main class="auth-page">
    <section class="auth-story">
      <div class="auth-story-inner">
        <div class="auth-brand">
          <span class="brand-mark"><AppIcon name="leaf" :size="22" /></span>
          <span>轻笺 <em>LeafNote</em></span>
        </div>
        <div class="auth-hero">
          <p class="eyebrow">A QUIET PLACE FOR NOTES</p>
          <h1>把想法安放在<br /><span>自己的群组里。</span></h1>
          <p class="auth-hero-copy">
            轻量 Markdown 笔记，多层文件夹，按群组严格隔离。<br />
            没有多余打扰，打开就能写。
          </p>
          <div class="auth-features">
            <div><AppIcon name="folder" :size="17" /><span>无限层级树形目录</span></div>
            <div><AppIcon name="shield" :size="17" /><span>数据库级群组隔离</span></div>
            <div><AppIcon name="key" :size="17" /><span>作者专属脚本沙箱</span></div>
          </div>
        </div>
        <p class="auth-story-foot">纯静态 · 无自建后端 · 可离线安装</p>
      </div>
      <div class="auth-leaf-deco" aria-hidden="true">
        <span></span><span></span><span></span>
      </div>
    </section>

    <section class="auth-panel">
      <div class="auth-card">
        <div class="auth-mobile-brand">
          <span class="brand-mark"><AppIcon name="leaf" :size="21" /></span>
          <span>轻笺 <em>LeafNote</em></span>
        </div>

        <div v-if="inviteCode" class="auth-invite-banner">
          <AppIcon name="users" :size="18" />
          <span>登录或注册后，将加入邀请码 <strong>{{ inviteCode }}</strong> 对应的群组。</span>
        </div>

        <div v-if="displayError" class="alert alert-error auth-alert">
          <AppIcon name="alert-triangle" :size="17" />
          <span>{{ displayError }}</span>
        </div>

        <template v-if="mode === 'sent'">
          <div class="auth-sent">
            <div class="auth-sent-icon"><AppIcon name="mail" :size="26" /></div>
            <p class="eyebrow">VERIFY YOUR EMAIL</p>
            <h2>去邮箱完成验证</h2>
            <p>
              验证邮件已发送至 <strong>{{ sentEmail }}</strong>。<br />
              点击邮件中的链接后，会自动回到这里登录。
            </p>
            <p class="muted small">没有收到？请检查垃圾邮件，或稍后重新发送。</p>
            <button class="btn btn-primary btn-block" type="button" :disabled="busy" @click="resend">
              <AppIcon v-if="busy" name="loader" :size="16" class="spin" />
              {{ busy ? '发送中…' : '重新发送验证邮件' }}
            </button>
            <button class="btn btn-ghost btn-block" type="button" @click="backToLogin">返回登录</button>
          </div>
        </template>

        <template v-else>
          <div class="auth-heading">
            <p class="eyebrow">{{ mode === 'login' ? 'WELCOME BACK' : 'CREATE ACCOUNT' }}</p>
            <h2>{{ mode === 'login' ? '登录轻笺' : '注册轻笺账号' }}</h2>
            <p>{{ mode === 'login' ? '继续整理你的笔记与群组。' : '使用邮箱注册，验证后即可开始。' }}</p>
          </div>

          <div class="auth-tabs" role="tablist" aria-label="登录或注册">
            <button
              type="button"
              role="tab"
              :aria-selected="mode === 'login'"
              :class="{ active: mode === 'login' }"
              @click="switchMode('login')"
            >
              登录
            </button>
            <button
              type="button"
              role="tab"
              :aria-selected="mode === 'register'"
              :class="{ active: mode === 'register' }"
              @click="switchMode('register')"
            >
              注册
            </button>
          </div>

          <form class="auth-form" @submit.prevent="submit">
            <label v-if="mode === 'register'" class="field">
              <span>用户名</span>
              <input
                v-model="form.username"
                type="text"
                maxlength="24"
                autocomplete="nickname"
                placeholder="2–24 个字符，可随时修改"
                required
              />
            </label>

            <label class="field">
              <span>邮箱</span>
              <input
                v-model="form.email"
                type="email"
                autocomplete="email"
                inputmode="email"
                placeholder="you@example.com"
                required
              />
            </label>

            <label class="field">
              <span>密码</span>
              <span class="password-field">
                <input
                  v-model="form.password"
                  :type="showPassword ? 'text' : 'password'"
                  :autocomplete="mode === 'login' ? 'current-password' : 'new-password'"
                  :placeholder="mode === 'login' ? '输入密码' : '至少 8 位字符'"
                  minlength="8"
                  required
                />
                <button
                  type="button"
                  class="password-toggle"
                  :aria-label="showPassword ? '隐藏密码' : '显示密码'"
                  @click="showPassword = !showPassword"
                >
                  <AppIcon :name="showPassword ? 'eye-off' : 'eye'" :size="17" />
                </button>
              </span>
            </label>

            <label v-if="mode === 'register'" class="field">
              <span>确认密码</span>
              <input
                v-model="form.confirm"
                :type="showPassword ? 'text' : 'password'"
                autocomplete="new-password"
                placeholder="再输入一次密码"
                minlength="8"
                required
              />
            </label>

            <p v-if="mode === 'login' && needsVerify" class="auth-inline-hint">
              还没有完成邮箱验证？
              <button type="button" class="text-link" :disabled="busy" @click="resend">
                重新发送验证邮件
              </button>
            </p>

            <button class="btn btn-primary btn-block auth-submit" type="submit" :disabled="busy || !online">
              <AppIcon v-if="busy" name="loader" :size="16" class="spin" />
              {{ busy ? '请稍候…' : mode === 'login' ? '登录' : '创建账号' }}
            </button>

            <p v-if="!online" class="offline-hint">
              <AppIcon name="cloud-off" :size="15" /> 当前处于离线状态，登录需要网络。
            </p>
          </form>

          <p class="auth-legal">
            注册即表示你同意仅将本服务用于合法用途。笔记数据保存在你配置的 Supabase 项目中。
          </p>
        </template>
      </div>
    </section>
  </main>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import AppIcon from './AppIcon.vue'
import { supabase } from '../lib/supabase'
import { errorMessage, isEmailValid, isUsernameValid } from '../lib/utils'
import { toast } from '../lib/toast'

const props = defineProps({
  initialError: { type: String, default: '' }
})

const mode = ref('login')
const form = reactive({ username: '', email: '', password: '', confirm: '' })
const busy = ref(false)
const showPassword = ref(false)
const sentEmail = ref('')
const needsVerify = ref(false)
const localError = ref('')
const online = ref(navigator.onLine)
const inviteCode = new URLSearchParams(window.location.search).get('invite') || ''

const displayError = computed(() => localError.value || props.initialError)

function goOnline() {
  online.value = true
}
function goOffline() {
  online.value = false
}

onMounted(() => {
  window.addEventListener('online', goOnline)
  window.addEventListener('offline', goOffline)
})
onBeforeUnmount(() => {
  window.removeEventListener('online', goOnline)
  window.removeEventListener('offline', goOffline)
})

function switchMode(next) {
  mode.value = next
  localError.value = ''
  needsVerify.value = false
}

function backToLogin() {
  mode.value = 'login'
  localError.value = ''
}

function redirectUrl() {
  const url = new URL(window.location.origin + window.location.pathname)
  if (inviteCode) url.searchParams.set('invite', inviteCode)
  return url.toString()
}

async function submit() {
  localError.value = ''
  needsVerify.value = false

  if (!online.value) {
    localError.value = '当前处于离线状态，请连接网络后再试。'
    return
  }
  if (!isEmailValid(form.email)) {
    localError.value = '请输入有效的邮箱地址。'
    return
  }
  if (form.password.length < 8) {
    localError.value = '密码至少需要 8 位字符。'
    return
  }
  if (mode.value === 'register') {
    if (!isUsernameValid(form.username)) {
      localError.value = '用户名需要 2–24 个字符，且不能包含控制字符。'
      return
    }
    if (form.password !== form.confirm) {
      localError.value = '两次输入的密码不一致。'
      return
    }
  }

  busy.value = true
  try {
    if (mode.value === 'login') {
      const { error } = await supabase.auth.signInWithPassword({
        email: form.email.trim(),
        password: form.password
      })
      if (error) throw error
      toast.success('欢迎回来')
      return
    }

    const { data, error } = await supabase.auth.signUp({
      email: form.email.trim(),
      password: form.password,
      options: {
        data: { username: form.username.trim() },
        emailRedirectTo: redirectUrl()
      }
    })
    if (error) throw error

    if (data?.session) {
      toast.success('账号已创建')
      return
    }
    sentEmail.value = form.email.trim()
    mode.value = 'sent'
  } catch (error) {
    const message = errorMessage(error, '操作失败，请稍后重试')
    localError.value = message
    if (/邮箱尚未验证/.test(message)) needsVerify.value = true
  } finally {
    busy.value = false
  }
}

async function resend() {
  const email = sentEmail.value || form.email.trim()
  if (!isEmailValid(email)) {
    localError.value = '请先填写邮箱。'
    return
  }
  busy.value = true
  localError.value = ''
  try {
    const { error } = await supabase.auth.resend({
      type: 'signup',
      email,
      options: { emailRedirectTo: redirectUrl() }
    })
    if (error) throw error
    toast.success('验证邮件已重新发送')
  } catch (error) {
    localError.value = errorMessage(error, '发送失败，请稍后重试')
  } finally {
    busy.value = false
  }
}
</script>
