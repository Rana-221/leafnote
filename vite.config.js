import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Relative base keeps the same build working at a GitHub Pages project path
// (https://user.github.io/repo/) as well as at a custom domain root.
export default defineConfig({
  base: './',
  plugins: [vue()],
  build: {
    target: 'es2020',
    cssCodeSplit: true,
    chunkSizeWarningLimit: 900,
    rollupOptions: {
      output: {
        manualChunks: {
          supabase: ['@supabase/supabase-js'],
          markdown: ['marked', 'dompurify', 'katex', 'highlight.js']
        }
      }
    }
  }
})
