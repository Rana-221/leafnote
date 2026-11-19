import { createApp } from 'vue'
import 'katex/dist/katex.min.css'
import 'highlight.js/styles/github.css'
import './styles.css'
import App from './App.vue'
import { toast } from './lib/toast'

const app = createApp(App)

app.config.errorHandler = (error, instance, info) => {
  console.error('LeafNote runtime error:', error, info)
  toast.error('页面遇到一个错误，请刷新后重试')
}

app.mount('#app')

if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    const swUrl = `${import.meta.env.BASE_URL}sw.js`
    navigator.serviceWorker.register(swUrl, { scope: import.meta.env.BASE_URL }).catch((error) => {
      console.warn('Service worker registration failed:', error)
    })
  })
}
