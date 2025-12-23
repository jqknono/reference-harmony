import { cp, mkdir, readdir, rm, stat, writeFile } from 'node:fs/promises'
import path from 'node:path'

const PROJECT_ROOT = process.cwd()
const SRC_MDS_DIR = path.join(PROJECT_ROOT, 'mds')
const DIST_DIR = path.join(PROJECT_ROOT, 'dist')
const DIST_MDS_DIR = path.join(DIST_DIR, 'mds')

function getArgValue(name) {
  const prefix = `--${name}=`
  const hit = process.argv.find((a) => a.startsWith(prefix))
  return hit ? hit.slice(prefix.length) : ''
}

function normalizeDomain(domain) {
  let d = (domain || '').trim()
  if (!d) return ''
  if (!/^https?:\/\//i.test(d)) d = `https://${d}`
  if (!d.endsWith('/')) d += '/'
  return d
}

function toDownloadUrl(domain, relPath) {
  if (!domain) return `/${relPath.replace(/\\/g, '/')}`
  return new URL(relPath.replace(/\\/g, '/'), domain).toString()
}

function humanKiB(bytes) {
  const kib = bytes / 1024
  if (kib < 1024) return `${kib.toFixed(1)} KiB`
  return `${(kib / 1024).toFixed(1)} MiB`
}

async function walkFiles(dirAbs, baseAbs) {
  const entries = await readdir(dirAbs, { withFileTypes: true })
  const out = []
  for (const e of entries) {
    const abs = path.join(dirAbs, e.name)
    if (e.isDirectory()) {
      out.push(...(await walkFiles(abs, baseAbs)))
      continue
    }
    if (e.isFile()) {
      out.push(path.relative(baseAbs, abs))
    }
  }
  return out
}

const domain = normalizeDomain(getArgValue('domain') || process.env.SITE_DOMAIN || '')
if (!domain) {
  console.error('缺少构建入参：--domain=你的域名（例如 --domain=https://xxx.github.io/reference-harmony/）')
  process.exit(1)
}

await rm(DIST_DIR, { recursive: true, force: true })
await mkdir(DIST_DIR, { recursive: true })

// 拷贝 mds 到 dist，保证下载链接可用
await mkdir(DIST_MDS_DIR, { recursive: true })
await cp(SRC_MDS_DIR, DIST_MDS_DIR, { recursive: true })

const relFiles = (await walkFiles(SRC_MDS_DIR, SRC_MDS_DIR))
  .filter((p) => !p.startsWith('.') && !p.includes(`${path.sep}.`))
  .sort((a, b) => a.localeCompare(b))

const rows = []
for (const rel of relFiles) {
  const abs = path.join(SRC_MDS_DIR, rel)
  const s = await stat(abs)
  if (!s.isFile()) continue

  const relUrlPath = `mds/${rel}`.replace(/\\/g, '/')
  const downloadUrl = toDownloadUrl(domain, relUrlPath)

  const mtime = new Date(s.mtimeMs).toISOString().replace('T', ' ').replace('Z', '')
  const size = humanKiB(s.size)

  rows.push(`
      <tr>
        <td class="path"><a href="${downloadUrl}" download>${relUrlPath}</a></td>
        <td class="size">${size}</td>
        <td class="mtime">${mtime}</td>
        <td class="action"><button class="btn" data-url="${downloadUrl}">复制链接</button></td>
      </tr>`.trim())
}

const html = `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>备忘清单 文件列表</title>
    <style>
      :root {
        color-scheme: light dark;
        --bg: Canvas;
        --fg: CanvasText;
        --muted: color-mix(in srgb, CanvasText 55%, Canvas 45%);
        --card: color-mix(in srgb, Canvas 92%, CanvasText 8%);
        --border: color-mix(in srgb, CanvasText 18%, Canvas 82%);
        --link: LinkText;
      }
      body {
        margin: 0;
        background: var(--bg);
        color: var(--fg);
        font: 1rem/1.55 system-ui, -apple-system, Segoe UI, Roboto, Noto Sans, Arial, "PingFang SC", "Microsoft YaHei", sans-serif;
      }
      .wrap {
        max-width: 72rem;
        margin: 0 auto;
        padding: 1.25rem;
      }
      header {
        display: grid;
        gap: 0.5rem;
        margin-bottom: 1rem;
      }
      h1 {
        font-size: 1.5rem;
        line-height: 1.2;
        margin: 0;
      }
      .meta {
        color: var(--muted);
        font-size: 0.95rem;
      }
      .card {
        background: var(--card);
        border: 0.0625rem solid var(--border);
        border-radius: 0.75rem;
        overflow: hidden;
      }
      .toolbar {
        display: grid;
        gap: 0.75rem;
        padding: 0.9rem 0.9rem 0.75rem;
        border-bottom: 0.0625rem solid var(--border);
      }
      .toolbar label {
        font-weight: 600;
        font-size: 0.95rem;
      }
      .toolbar input {
        width: 100%;
        border: 0.0625rem solid var(--border);
        border-radius: 0.6rem;
        padding: 0.65rem 0.75rem;
        background: var(--bg);
        color: var(--fg);
        outline: none;
      }
      table {
        width: 100%;
        border-collapse: collapse;
      }
      thead th {
        text-align: left;
        font-weight: 700;
        font-size: 0.95rem;
        padding: 0.75rem 0.9rem;
        border-bottom: 0.0625rem solid var(--border);
        background: color-mix(in srgb, var(--card) 90%, var(--bg) 10%);
      }
      tbody td {
        padding: 0.75rem 0.9rem;
        border-bottom: 0.0625rem solid var(--border);
        vertical-align: top;
      }
      tbody tr:hover {
        background: color-mix(in srgb, var(--card) 84%, var(--bg) 16%);
      }
      a {
        color: var(--link);
        text-decoration: none;
      }
      a:hover {
        text-decoration: underline;
      }
      .path {
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, "Liberation Mono", monospace;
        font-size: 0.95rem;
        word-break: break-word;
      }
      .size, .mtime {
        white-space: nowrap;
        color: var(--muted);
        font-size: 0.95rem;
      }
      .action {
        white-space: nowrap;
      }
      .btn {
        display: inline-block;
        padding: 0.45rem 0.65rem;
        border: 0.0625rem solid var(--border);
        border-radius: 0.6rem;
        background: var(--bg);
        color: var(--fg);
        cursor: pointer;
        font: inherit;
      }
      .btn:hover {
        background: color-mix(in srgb, var(--bg) 90%, var(--fg) 10%);
      }
      .btn.copied {
        background: #22c55e;
        color: #fff;
        border-color: #22c55e;
      }
      @media (max-width: 48rem) {
        thead th:nth-child(3), tbody td:nth-child(3) { display: none; }
      }
      @media (max-width: 36rem) {
        thead th:nth-child(2), tbody td:nth-child(2) { display: none; }
      }
    </style>
  </head>
  <body>
    <div class="wrap">
      <header>
        <h1>备忘清单 文件列表</h1>
        <div class="meta">
          开源地址：<a href="https://github.com/jqknono/reference-harmony" target="_blank" rel="noreferrer">GitHub</a> · 文件数：<span id="count"></span>
        </div>
      </header>

      <div class="card">
        <div class="toolbar">
          <div>
            <label for="q">搜索（按路径过滤）</label>
            <input id="q" type="search" placeholder="例如：mds/zh/git" autocomplete="off" />
          </div>
        </div>

        <div style="overflow:auto">
          <table>
            <thead>
              <tr>
                <th>文件</th>
                <th>大小</th>
                <th>修改时间</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody id="tbody">
${rows.map((r) => `              ${r}`).join('\n')}
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <script>
      (function () {
        var tbody = document.getElementById('tbody');
        var rows = Array.prototype.slice.call(tbody.querySelectorAll('tr'));
        document.getElementById('count').textContent = String(rows.length);
        var input = document.getElementById('q');
        input.addEventListener('input', function () {
          var q = (input.value || '').trim().toLowerCase();
          var shown = 0;
          rows.forEach(function (tr) {
            var text = (tr.querySelector('.path') || tr).textContent.toLowerCase();
            var ok = !q || text.indexOf(q) !== -1;
            tr.style.display = ok ? '' : 'none';
            if (ok) shown++;
          });
          document.getElementById('count').textContent = String(shown);
        });

        // 复制链接功能
        tbody.addEventListener('click', function (e) {
          var btn = e.target.closest('.btn[data-url]');
          if (!btn) return;
          var url = btn.getAttribute('data-url');
          navigator.clipboard.writeText(url).then(function () {
            var orig = btn.textContent;
            btn.textContent = '已复制';
            btn.classList.add('copied');
            setTimeout(function () {
              btn.textContent = orig;
              btn.classList.remove('copied');
            }, 1500);
          });
        });
      })();
    </script>
  </body>
</html>
`

await writeFile(path.join(DIST_DIR, 'index.html'), html, 'utf8')
console.log(`已生成：${path.relative(PROJECT_ROOT, path.join(DIST_DIR, 'index.html'))}`)



