import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const WEB_ROOT = path.resolve(__dirname, '..');
const REPO_ROOT = path.resolve(WEB_ROOT, '..', '..');
const MDS_DIR = path.join(REPO_ROOT, 'mds');
const REFERENCE_ICONS_DIR = path.join(
  REPO_ROOT,
  'entry',
  'src',
  'main',
  'resources',
  'rawfile',
  'reference',
  'icons',
);
const OUT_PUBLIC_DIR = path.join(WEB_ROOT, 'public');
const OUT_FILE = path.join(OUT_PUBLIC_DIR, 'catalog.json');

function safeIdFromPath(relativePath) {
  const raw = String(relativePath ?? '').replace(/\.md$/i, '').replace(/[\\/]/g, '_');
  const normalized = raw.normalize('NFKD').replace(/[^\w-]/g, '_');
  const compact = normalized.replace(/_+/g, '_').replace(/^_+|_+$/g, '');
  return compact || 'doc';
}

function cleanHeadingText(text) {
  return String(text ?? '')
    .replace(/\\<\s*\/\s*>\s*/g, '')
    .replace(/\s*\{[^}]*\}\s*$/, '')
    .trim();
}

function stripHtmlCommentsInLine(line) {
  return String(line ?? '').replace(/<!--[\s\S]*?-->/g, '');
}

function isSetextUnderline(line, ch) {
  const t = String(line ?? '').trim();
  if (!t) return false;
  if (ch === '=') return /^={3,}$/.test(t);
  if (ch === '-') return /^-{3,}$/.test(t);
  return /^={3,}$/.test(t) || /^-{3,}$/.test(t);
}

function getSetextHeading(lines, i) {
  if (i + 1 >= lines.length) return undefined;
  const text = stripHtmlCommentsInLine(lines[i] ?? '').trim();
  if (!text) return undefined;
  const underline = stripHtmlCommentsInLine(lines[i + 1] ?? '').trim();
  if (isSetextUnderline(underline, '=')) return { level: 1, text };
  if (isSetextUnderline(underline, '-')) return { level: 2, text };
  return undefined;
}

function extractFrontmatter(markdown) {
  const normalized = String(markdown ?? '').replace(/\r\n/g, '\n');
  if (!normalized.startsWith('---\n')) return { frontmatter: {}, body: normalized };
  const end = normalized.indexOf('\n---\n', 4);
  if (end === -1) return { frontmatter: {}, body: normalized };
  const block = normalized.slice(4, end);
  const body = normalized.slice(end + '\n---\n'.length);

  const frontmatter = {};
  const lines = block.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const m = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (!m) continue;
    const key = m[1];
    const rawValue = String(m[2] ?? '').trim();

    if (key === 'title') {
      frontmatter.title = rawValue.replace(/^['"]|['"]$/g, '').trim();
      continue;
    }

    if (key === 'intro') {
      if (rawValue === '|' || rawValue === '>') {
        const buf = [];
        i++;
        while (i < lines.length) {
          const l = lines[i];
          if (!/^\s{2,}\S/.test(l) && l.trim() !== '') break;
          buf.push(l.replace(/^\s{2}/, ''));
          i++;
        }
        i--;
        frontmatter.intro = buf.join('\n').trim();
      } else {
        frontmatter.intro = rawValue.replace(/^['"]|['"]$/g, '').trim();
      }
    }
  }

  return { frontmatter, body };
}

function extractDocNameAndTitle(markdown, fallbackId) {
  const { frontmatter, body } = extractFrontmatter(markdown);
  const lines = body.replace(/\r\n/g, '\n').split('\n');

  const frontName = String(frontmatter.title ?? '').trim();
  const frontIntro = String(frontmatter.intro ?? '').trim();
  if (frontName) {
    return { name: frontName, title: frontIntro || frontName };
  }

  let name = String(fallbackId ?? '').trim() || 'doc';
  let title = '';
  let h1Index = -1;
  let h1IsSetext = false;

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    if (!rawLine) continue;
    const line = stripHtmlCommentsInLine(rawLine);
    if (!line.trim()) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;

    const setext = getSetextHeading(lines, i);
    if (setext?.level === 1) {
      name = cleanHeadingText(setext.text);
      h1Index = i;
      h1IsSetext = true;
      break;
    }

    const atx1 = /^#\s+(.+)$/.exec(line);
    if (atx1) {
      name = cleanHeadingText(atx1[1].trim());
      h1Index = i;
      break;
    }
  }

  const start = h1Index === -1 ? 0 : (h1IsSetext ? h1Index + 2 : h1Index + 1);
  for (let i = start; i < lines.length; i++) {
    const rawLine = lines[i];
    if (!rawLine) continue;
    const line = stripHtmlCommentsInLine(rawLine);
    if (!line.trim()) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;

    const setext = getSetextHeading(lines, i);
    if (setext?.level === 2) break;
    if (/^##\s+/.test(line)) break;
    if (/^#{1,6}\s+/.test(line)) continue;
    if (isSetextUnderline(line)) continue;

    const t = line.trim();
    if (t) {
      title = t;
      break;
    }
  }

  return { name, title: title || name };
}

async function walkMarkdownFiles(dirAbs, baseAbs) {
  const entries = await fs.readdir(dirAbs, { withFileTypes: true });
  const out = [];
  for (const e of entries) {
    const abs = path.join(dirAbs, e.name);
    if (e.isDirectory()) {
      out.push(...(await walkMarkdownFiles(abs, baseAbs)));
      continue;
    }
    if (e.isFile()) {
      const lower = e.name.toLowerCase();
      if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
        out.push(path.relative(baseAbs, abs).replace(/\\/g, '/'));
      }
    }
  }
  return out;
}

function formatIso(ms) {
  return new Date(ms).toISOString();
}

async function listSvgIconIds(dirAbs) {
  const entries = await fs.readdir(dirAbs, { withFileTypes: true }).then(
    (v) => v,
    () => [],
  );
  const out = new Set();
  for (const e of entries) {
    if (!e?.isFile?.()) continue;
    const name = String(e.name ?? '');
    if (!name.toLowerCase().endsWith('.svg')) continue;
    const base = name.slice(0, -'.svg'.length);
    if (base) out.add(base);
  }
  return out;
}

async function buildCatalog() {
  const langs = ['zh', 'en'];
  const items = [];
  const iconSetByLang = new Map();

  for (const lang of langs) {
    const langDir = path.join(MDS_DIR, lang);
    const langOk = await fs.stat(langDir).then((s) => s?.isDirectory() ?? false, () => false);
    if (!langOk) continue;

    if (!iconSetByLang.has(lang)) {
      const iconDir = path.join(REFERENCE_ICONS_DIR, lang);
      iconSetByLang.set(lang, await listSvgIconIds(iconDir));
    }
    const iconIds = iconSetByLang.get(lang) ?? new Set();

    const rels = await walkMarkdownFiles(langDir, langDir);
    rels.sort((a, b) => a.localeCompare(b));

    for (const rel of rels) {
      const abs = path.join(langDir, rel);
      const st = await fs.stat(abs);
      const fallbackId = safeIdFromPath(rel);
      const meta = await fs.readFile(abs, 'utf8').then(
        (md) => extractDocNameAndTitle(md, fallbackId),
        () => ({ name: fallbackId, title: fallbackId }),
      );
      items.push({
        id: `cloud_${fallbackId}`,
        lang,
        relPath: `${lang}/${rel}`.replace(/\\/g, '/'),
        mdUrl: `mds/${lang}/${rel}`.replace(/\\/g, '/'),
        name: meta.name || fallbackId,
        title: meta.title || meta.name || fallbackId,
        icon: iconIds.has(fallbackId) ? `reference/icons/${lang}/${fallbackId}.svg` : undefined,
        size: st.size,
        mtimeMs: st.mtimeMs,
        mtimeIso: formatIso(st.mtimeMs),
      });
    }
  }

  return {
    version: 1,
    builtAt: formatIso(Date.now()),
    items,
  };
}

await fs.mkdir(OUT_PUBLIC_DIR, { recursive: true });
const data = await buildCatalog();
await fs.writeFile(OUT_FILE, JSON.stringify(data, null, 2), 'utf8');
// eslint-disable-next-line no-console
console.log(`[online-web] generated: ${path.relative(WEB_ROOT, OUT_FILE)} items=${data.items.length}`);

