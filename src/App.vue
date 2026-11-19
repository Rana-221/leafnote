<template>
  <div class="app-root">
    <template v-if="!isSupabaseConfigured">
      <section class="setup-screen">
        <div class="setup-card">
          <div class="brand-mark large"><AppIcon name="leaf" :size="30" /></div>
          <p class="eyebrow">LEAFNOTE · 初始配置</p>
          <h1>还差一步，连接你的 Supabase</h1>
          <p class="setup-lead">
            这是一个纯静态前端。复制环境变量文件，填入项目地址与 anon key，然后重新构建即可。
          </p>
          <ol class="setup-steps">
            <li>在 Supabase SQL Editor 中执行 <code>supabase/schema.sql</code></li>
            <li>创建 <code>.env</code>（可参考 <code>.env.example</code>）</li>
            <li>运行 <code>npm install &amp;&amp; npm run build</code></li>
          </ol>
          <pre class="setup-code"><code>VITE_SUPABASE_URL=https://your-project-ref.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key</code></pre>
          <p class="setup-note">
            只使用 anon / publishable key。永远不要把 service_role key 放进前端。
          </p>
        </div>
      </section>
    </template>

    <template v-else-if="!ready">
      <div class="boot-screen">
        <div class="brand-mark large"><AppIcon name="leaf" :size="30" /></div>
        <div class="boot-spinner" aria-label="正在加载"></div>
        <p>正在打开轻笺…</p>
      </div>
    </template>

    <AuthView
      v-else-if="!session"
      :initial-error="bootError"
    />

    <Workspace
      v-else
      :session="session"
      @signed-out="session = null"
    />

    <ToastHost />
  </div>
</template>

<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue'
import AppIcon from './components/AppIcon.vue'
import AuthView from './components/AuthView.vue'
import Workspace from './components/Workspace.vue'
import ToastHost from './components/ToastHost.vue'
import { isSupabaseConfigured, supabase } from './lib/supabase'

const ready = ref(false)
const session = ref(null)
const bootError = ref('')
let unsubscribe = null

function readUrlError() {
  const raw = `${window.location.search}&${window.location.hash.replace(/^#/, '')}`
  const params = new URLSearchParams(raw)
  const message = params.get('error_description') || params.get('error')
  if (!message) return ''
  window.history.replaceState({}, '', window.location.pathname)
  return message.replace(/\+/g, ' ')
}

onMounted(async () => {
  bootError.value = readUrlError()
  if (!isSupabaseConfigured) {
    ready.value = true
    return
  }

  const { data, error } = await supabase.auth.getSession()
  if (error && !bootError.value) bootError.value = error.message
  const initialSession = data?.session ?? null
  if (initialSession && !initialSession.user.email_confirmed_at) {
    bootError.value = '邮箱尚未验证。请先打开验证邮件中的链接，再登录轻笺。'
    await supabase.auth.signOut({ scope: 'local' })
    session.value = null
  } else {
    session.value = initialSession
  }

  const listener = supabase.auth.onAuthStateChange((event, nextSession) => {
    if (nextSession && !nextSession.user.email_confirmed_at) {
      session.value = null
      bootError.value = '邮箱尚未验证。请先打开验证邮件中的链接，再登录轻笺。'
      window.setTimeout(() => {
        supabase.auth.signOut({ scope: 'local' }).catch(() => {})
      }, 0)
      return
    }
    session.value = nextSession
    if (nextSession && event !== 'TOKEN_REFRESHED') bootError.value = ''
  })
  unsubscribe = () => listener.data.subscription.unsubscribe()
  ready.value = true
})

onBeforeUnmount(() => {
  unsubscribe?.()
})
</script>
