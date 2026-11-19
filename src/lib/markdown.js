import { Marked } from 'marked'
import DOMPurify from 'dompurify'
import katex from 'katex'
import hljs from 'highlight.js/lib/core'
import javascript from 'highlight.js/lib/languages/javascript'
import typescript from 'highlight.js/lib/languages/typescript'
import json from 'highlight.js/lib/languages/json'
import xml from 'highlight.js/lib/languages/xml'
import css from 'highlight.js/lib/languages/css'
import bash from 'highlight.js/lib/languages/bash'
import shell from 'highlight.js/lib/languages/shell'
import python from 'highlight.js/lib/languages/python'
import java from 'highlight.js/lib/languages/java'
import c from 'highlight.js/lib/languages/c'
import cpp from 'highlight.js/lib/languages/cpp'
import csharp from 'highlight.js/lib/languages/csharp'
import go from 'highlight.js/lib/languages/go'
import rust from 'highlight.js/lib/languages/rust'
import php from 'highlight.js/lib/languages/php'
import ruby from 'highlight.js/lib/languages/ruby'
import sql from 'highlight.js/lib/languages/sql'
import yaml from 'highlight.js/lib/languages/yaml'
import markdown from 'highlight.js/lib/languages/markdown'
import diff from 'highlight.js/lib/languages/diff'
import dockerfile from 'highlight.js/lib/languages/dockerfile'
import ini from 'highlight.js/lib/languages/ini'

for (const [name, language] of Object.entries({
  javascript,
  typescript,
  json,
  xml,
  css,
  bash,
  shell,
  python,
  java,
  c,
  cpp,
  csharp,
  go,
  rust,
  php,
  ruby,
  sql,
  yaml,
  markdown,
  diff,
  dockerfile,
  ini
})) {
  hljs.registerLanguage(name, language)
}

const SCRIPT_LANGS = new Set(['script', 'custom-script', 'js-run'])
const SANITIZE_OPTIONS = {
  USE_PROFILES: { html: true },
  FORBID_TAGS: [
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'form',
    'textarea',
    'select',
    'option',
    'button',
    'base',
    'link',
    'meta'
  ],
  FORBID_ATTR: ['srcdoc', 'formaction', 'style'],
  ALLOW_DATA_ATTR: true
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function sanitizeLanguage(value) {
  return String(value || '').replace(/[^\w-]/g, '')
}

let renderSequence = 0

function createMarked(scripts, mathBlocks) {
  let mathSeq = 0
  let scriptSeq = 0
  const renderId = ++renderSequence

  const mathBlock = {
    name: 'mathBlock',
    level: 'block',
    start(src) {
      const index = src.indexOf('$$')
      return index >= 0 ? index : undefined
    },
    tokenizer(src) {
      const match = /^\$\$[ \t]*\r?\n?([\s\S]+?)\r?\n?\$\$[ \t]*(?:\r?\n+|$)/.exec(src)
      if (!match) return undefined
      return { type: 'mathBlock', raw: match[0], text: match[1].trim() }
    },
    renderer(token) {
      if (!token.text) return ''
      const id = `m${renderId}-${++mathSeq}`
      mathBlocks.set(id, { text: token.text, display: true })
      return `<div class="math-slot" data-math-id="${id}"></div>\n`
    }
  }

  const mathInline = {
    name: 'mathInline',
    level: 'inline',
    start(src) {
      const index = src.indexOf('$')
      return index >= 0 ? index : undefined
    },
    tokenizer(src) {
      const match = /^\$(?!\$)([^\n$]+?)\$(?![\d$])/.exec(src)
      if (!match || !match[1].trim()) return undefined
      return { type: 'mathInline', raw: match[0], text: match[1].trim() }
    },
    renderer(token) {
      const id = `m${renderId}-${++mathSeq}`
      mathBlocks.set(id, { text: token.text, display: false })
      return `<span class="math-slot" data-math-id="${id}"></span>`
    }
  }

  const renderer = {
    code(token) {
      const raw = token.text ?? ''
      const info = (token.lang || '').trim().split(/\s+/)[0].toLowerCase()
      if (SCRIPT_LANGS.has(info)) {
        const id = `s${renderId}-${++scriptSeq}`
        scripts.set(id, { id, code: raw })
        return `<div class="script-slot" data-script-id="${id}"></div>\n`
      }

      let highlighted
      const language = sanitizeLanguage(info)
      if (language && hljs.getLanguage(language)) {
        highlighted = hljs.highlight(raw, {
          language,
          ignoreIllegals: true
        }).value
      } else {
        highlighted = escapeHtml(raw)
      }

      const label = escapeHtml(info || 'code')
      const className = language ? ` language-${language}` : ''
      return `<div class="code-block"><div class="code-block-bar"><span>${label}</span></div><pre><code class="hljs${className}">${highlighted}</code></pre></div>`
    }
  }

  const parser = new Marked({ gfm: true, breaks: true })
  parser.use({ extensions: [mathBlock, mathInline], renderer })
  return parser
}

/**
 * Render untrusted Markdown to HTML.
 *
 * Script fences are never turned into inline executable HTML. They become
 * empty slots hydrated by Vue after sanitization; the code is put in an iframe
 * with sandbox="allow-scripts" only when the note author clicks Run.
 */
export function renderMarkdown(source) {
  const scripts = new Map()
  const mathBlocks = new Map()
  const parser = createMarked(scripts, mathBlocks)

  const rawHtml = parser.parse(source || '')
  // Allow only disabled task-list checkboxes. Everything else <input> is
  // removed before it ever reaches the page.
  DOMPurify.addHook('uponSanitizeElement', (node, data) => {
    if (data.tagName !== 'input') return
    const type = (node.getAttribute('type') || '').toLowerCase()
    if (type !== 'checkbox' || !node.hasAttribute('disabled')) {
      node.parentNode?.removeChild(node)
    }
  })
  let clean
  try {
    clean = DOMPurify.sanitize(rawHtml, SANITIZE_OPTIONS)
  } finally {
    DOMPurify.removeHook('uponSanitizeElement')
  }
  const holder = document.createElement('div')
  holder.innerHTML = clean

  for (const slot of holder.querySelectorAll('[data-math-id]')) {
    const item = mathBlocks.get(slot.getAttribute('data-math-id'))
    if (!item) {
      slot.remove()
      continue
    }
    try {
      slot.outerHTML = katex.renderToString(item.text, {
        displayMode: item.display,
        throwOnError: false,
        strict: 'ignore',
        trust: false,
        output: 'htmlAndMathml'
      })
    } catch {
      slot.outerHTML = `<code class="math-error">${escapeHtml(item.text)}</code>`
    }
  }

  for (const link of holder.querySelectorAll('a')) {
    link.setAttribute('target', '_blank')
    link.setAttribute('rel', 'noopener noreferrer nofollow')
  }
  for (const image of holder.querySelectorAll('img')) {
    image.setAttribute('loading', 'lazy')
    image.setAttribute('decoding', 'async')
    image.setAttribute('referrerpolicy', 'no-referrer')
  }
  for (const checkbox of holder.querySelectorAll('input[type="checkbox"]')) {
    checkbox.disabled = true
    checkbox.setAttribute('disabled', '')
    checkbox.parentElement?.classList.add('task-list-item')
  }

  return {
    html: holder.innerHTML,
    scripts: Array.from(scripts.values())
  }
}

function scriptSafe(code) {
  return String(code)
    .replace(/<\/script/gi, '<\\/script')
    .replace(/<!--/g, '<\\!--')
}

function buildScriptDocument(code, scriptId) {
  const safeCode = scriptSafe(code)
  const id = JSON.stringify(scriptId)
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; connect-src 'none'; media-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: light; }
  html, body { margin: 0; padding: 0; background: #fbfaf5; color: #243029; }
  body { font: 13px/1.65 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; padding: 12px 14px; overflow-wrap: anywhere; }
  * { box-sizing: border-box; }
  pre { margin: 0; white-space: pre-wrap; }
  button { font: inherit; }
</style>
</head>
<body>
<script>
(function () {
  var id = ${id};
  function send() {
    var h = Math.max(48, Math.min(1200, Math.ceil(document.documentElement.scrollHeight)));
    try { parent.postMessage({ __leafnoteScript: id, height: h }, '*'); } catch (e) {}
  }
  if (window.ResizeObserver) {
    new ResizeObserver(send).observe(document.documentElement);
  }
  window.addEventListener('load', send);
  setTimeout(send, 60);
})();
</script>
<script>
${safeCode}
</script>
</body>
</html>`
}

function runScript(script, frame) {
  frame.hidden = false
  frame.classList.add('is-visible')
  frame.srcdoc = buildScriptDocument(script.code, script.id).replace(
    '</head>',
    `<!--run:${Date.now()}--></head>`
  )
}

export function hydrateScriptBlocks(container, scripts, options = {}) {
  if (!container) return
  const scriptMap = new Map(scripts.map((script) => [script.id, script]))
  const canRunScripts = Boolean(options.canRunScripts)

  for (const slot of container.querySelectorAll('[data-script-id]')) {
    const script = scriptMap.get(slot.getAttribute('data-script-id'))
    if (!script || slot.dataset.hydrated === '1') continue
    slot.dataset.hydrated = '1'
    slot.classList.add('script-block')

    const header = document.createElement('div')
    header.className = 'script-block-head'

    const title = document.createElement('span')
    title.className = 'script-block-title'
    title.textContent = 'SCRIPT'
    header.appendChild(title)

    const safety = document.createElement('span')
    safety.className = 'script-block-safety'
    safety.textContent = canRunScripts ? '作者沙箱' : '仅展示源码'
    header.appendChild(safety)

    let frame = null
    if (canRunScripts) {
      const actions = document.createElement('span')
      actions.className = 'script-block-actions'

      const runButton = document.createElement('button')
      runButton.type = 'button'
      runButton.className = 'script-run-btn'
      runButton.textContent = '运行脚本'
      runButton.title = '在隔离的 sandbox iframe 中运行；无法访问本站数据'
      actions.appendChild(runButton)
      header.appendChild(actions)

      frame = document.createElement('iframe')
      frame.className = 'script-frame'
      frame.setAttribute('sandbox', 'allow-scripts')
      frame.setAttribute('referrerpolicy', 'no-referrer')
      frame.setAttribute('title', '笔记自定义脚本沙箱输出')
      frame.hidden = true
      frame.dataset.scriptFrame = script.id

      runButton.addEventListener('click', () => {
        runScript(script, frame)
        runButton.textContent = '重新运行'
        runButton.classList.add('has-run')
      })
    } else {
      const note = document.createElement('span')
      note.className = 'script-block-note'
      note.textContent = '只有笔记作者查看时可运行'
      header.appendChild(note)
    }

    const pre = document.createElement('pre')
    pre.className = 'script-source'
    const codeEl = document.createElement('code')
    codeEl.textContent = script.code
    pre.appendChild(codeEl)

    slot.appendChild(header)
    slot.appendChild(pre)
    if (frame) slot.appendChild(frame)
  }
}

export function clampScriptFrameHeight(value) {
  const number = Number(value)
  if (!Number.isFinite(number)) return 0
  return Math.max(48, Math.min(1200, Math.round(number)))
}
