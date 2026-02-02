import http from 'node:http';
import { createReadStream } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const DEFAULT_MDS_DIR = path.join(REPO_ROOT, 'mds');
const DEFAULT_REFERENCE_ICONS_DIR = path.join(
  REPO_ROOT,
  'entry',
  'src',
  'main',
  'resources',
  'rawfile',
  'reference',
  'icons',
);
const DEFAULT_SHARES_DIR = path.join(REPO_ROOT, 'online', 'server', 'data', 'shares');

function envString(name, fallback) {
  const v = String(process.env[name] ?? '').trim();
  return v ? v : fallback;
}

function envNumber(name, fallback) {
  const raw = String(process.env[name] ?? '').trim();
  const n = raw ? Number(raw) : NaN;
  return Number.isFinite(n) ? n : fallback;
}

const MDS_DIR = path.resolve(envString('MDS_DIR', DEFAULT_MDS_DIR));
const PORT = envNumber('PORT', 5179);
const PUBLIC_ORIGIN = envString('PUBLIC_ORIGIN', '');
const SHARES_DIR = path.resolve(envString('SHARES_DIR', DEFAULT_SHARES_DIR));

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

function isProbablyAutolinkInner(inner) {
  const s = String(inner ?? '').trim();
  if (!s) return false;
  if (/\s/.test(s)) return false;
  if (/^(https?:\/\/|mailto:|tel:)/i.test(s)) return true;
  if (s.includes('@') && /^[^@]+@[^@]+\.[^@]+$/.test(s)) return true;
  return false;
}

function stripTagsInLine(line) {
  // Keep behavior aligned with `tools/sync_reference_docs.mjs` / `markdownDocParser.ets`:
  // - Preserve inline-code
  // - Preserve autolinks like <https://...> / <user@a.b>
  // - Convert <br> into literal "\\n" (2 chars) to avoid breaking table parsing
  const s = String(line ?? '');
  let out = '';
  let inInlineCode = false;
  let inlineFenceLen = 0;

  const countBackticksAt = (idx) => {
    let n = 0;
    while (idx + n < s.length && s[idx + n] === '`') n++;
    return n;
  };

  const isEscapedByBackslashes = (idx) => {
    let n = 0;
    for (let j = idx - 1; j >= 0 && s[j] === '\\'; j--) n++;
    return n % 2 === 1;
  };

  const findClosingBacktickRun = (fromIdx, fenceLen) => {
    for (let j = fromIdx; j < s.length; j++) {
      if (s[j] !== '`') continue;
      const run = countBackticksAt(j);
      if (run === fenceLen) return j;
      j += run - 1;
    }
    return -1;
  };

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];

    if (ch === '`') {
      const run = countBackticksAt(i);
      const escaped = isEscapedByBackslashes(i);
      if (!inInlineCode) {
        if (!escaped) {
          const close = findClosingBacktickRun(i + run, run);
          if (close !== -1) {
            inInlineCode = true;
            inlineFenceLen = run;
          }
        }
      } else if (run === inlineFenceLen) {
        inInlineCode = false;
        inlineFenceLen = 0;
      }
      out += '`'.repeat(run);
      i += run - 1;
      continue;
    }

    if (!inInlineCode) {
      if (ch === '\\' && i + 1 < s.length && s[i + 1] === '<') {
        out += ch;
        out += '<';
        i += 1;
        continue;
      }
      if (ch === '<') {
        const end = s.indexOf('>', i + 1);
        if (end === -1) {
          out += ch;
          continue;
        }
        const inner = s.slice(i + 1, end);
        const lowerInner = inner.trim().toLowerCase();
        if (lowerInner.startsWith('br') && (lowerInner.length === 2 || /^[\s/]/.test(lowerInner.slice(2)))) {
          out += '\\n';
          i = end;
          continue;
        }
        if (isProbablyAutolinkInner(inner)) {
          out += inner.trim();
          i = end;
          continue;
        }
        const first = inner.charAt(0);
        if (first && !/\s/.test(first)) {
          i = end;
          continue;
        }
        out += ch;
        continue;
      }
    }

    out += ch;
  }

  return out;
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

    if (key === 'icon') {
      frontmatter.icon = rawValue.replace(/^['"]|['"]$/g, '').trim();
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
  const frontIcon = String(frontmatter.icon ?? '').trim();
  if (frontName) {
    return { name: frontName, title: frontIntro || frontName, icon: frontIcon, frontmatter, body };
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

  return { name, title: title || name, icon: frontIcon, frontmatter, body };
}

function parseFenceOpen(line) {
  const m = /^\s*(`{3,}|~{3,})\s*([^\n]*)$/.exec(String(line ?? ''));
  if (!m) return undefined;
  const info = String(m[2] ?? '').trim();
  const lang = info.split(/\s+/)[0] ?? '';
  return { marker: m[1], lang, info };
}

function isFenceClose(line, marker) {
  const t = String(line ?? '').trim();
  if (!t) return false;
  const ch = marker[0];
  if (t.length < marker.length) return false;
  for (let i = 0; i < t.length; i++) {
    if (t[i] !== ch) return false;
  }
  return true;
}

function isRehypeIgnoreStart(line) {
  return /^\s*<!--\s*rehype:ignore:start\s*-->\s*$/.test(String(line ?? ''));
}

function isRehypeIgnoreEnd(line) {
  return /^\s*<!--\s*rehype:ignore:end\s*-->\s*$/.test(String(line ?? ''));
}

function isHtmlPreviewFence(fence) {
  const info = String(fence?.info ?? '').trim().toLowerCase();
  return /^html\s+preview(\s|$)/.test(info);
}

function isHorizontalRuleLine(line) {
  const t = String(line ?? '').trim();
  if (!t) return false;
  return /^(-{3,}|\*{3,}|_{3,})$/.test(t);
}

function splitTableRow(line) {
  let s = String(line ?? '').trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);

  const cells = [];
  let current = '';
  let inInlineCode = false;

  const isEscapedByBackslashes = (idx) => {
    let n = 0;
    for (let j = idx - 1; j >= 0 && s[j] === '\\'; j--) n++;
    return n % 2 === 1;
  };

  for (let i = 0; i < s.length; i++) {
    const ch = s[i];

    if (ch === '\\' && i + 1 < s.length) {
      const next = s[i + 1];
      if (next === '|') {
        current += '|';
        i += 1;
        continue;
      }
      current += ch;
      continue;
    }

    if (ch === '`') {
      if (inInlineCode) {
        inInlineCode = false;
      } else {
        const escaped = isEscapedByBackslashes(i);
        const hasClose = s.indexOf('`', i + 1) >= 0;
        if (!escaped && hasClose) {
          inInlineCode = true;
        }
      }
      current += ch;
      continue;
    }

    if (ch === '|' && !inInlineCode) {
      cells.push(current.trim());
      current = '';
      continue;
    }

    current += ch;
  }

  cells.push(current.trim());
  return cells;
}

function isTableSeparatorLine(line) {
  const trimmed = stripHtmlCommentsInLine(line).trim();
  if (!trimmed.includes('|')) return false;
  if (/[^|\s:-]/.test(trimmed)) return false;
  const cells = splitTableRow(trimmed);
  if (cells.length === 0) return false;
  for (const cell of cells) {
    const c = String(cell ?? '').replace(/\s+/g, '');
    if (!/^:?-{3,}:?$/.test(c)) return false;
  }
  return true;
}

function isListItem(line) {
  return /^\s*([-*+]|(\d+\.))\s+/.test(String(line ?? ''));
}

function stripListMarker(line) {
  return String(line ?? '').replace(/^\s*([-*+]|(\d+\.))\s+/, '').trim();
}

function countSectionsAndCards(frontmatter, body, lang, keepTags = false) {
  const lines = String(body ?? '').replace(/\r\n/g, '\n').split('\n');
  const introTitle = lang === 'en' ? 'Intro' : '简介';

  let sectionCount = 1;
  let currentSectionId = 'intro';
  let currentSectionTitle = introTitle;

  let lastH3 = '';
  let lastH4 = '';
  let h3TitleUsed = false;
  let h4TitleUsed = false;
  let consumedDocHeading = false;

  let cardCount = 0;
  let lastCountedSectionId = '';

  const normalizeLine = (raw) => {
    const withoutComments = stripHtmlCommentsInLine(raw);
    if (keepTags) return withoutComments;
    return stripTagsInLine(withoutComments);
  };

  const resetHeadingState = () => {
    lastH3 = '';
    lastH4 = '';
    h3TitleUsed = false;
    h4TitleUsed = false;
  };

  const setH3 = (titleText) => {
    lastH3 = titleText;
    lastH4 = '';
    h3TitleUsed = false;
    h4TitleUsed = false;
  };

  const setH4 = (titleText) => {
    lastH4 = titleText;
    h4TitleUsed = false;
  };

  const nextCardTitle = () => {
    if (currentSectionId === 'intro') return currentSectionTitle;
    if (lastH4 && lastH3 && !h3TitleUsed) {
      h3TitleUsed = true;
      h4TitleUsed = true;
      return `${lastH3} - ${lastH4}`;
    }
    if (lastH4) {
      if (!h4TitleUsed) {
        h4TitleUsed = true;
        return lastH4;
      }
      return '';
    }
    if (lastH3) {
      if (!h3TitleUsed) {
        h3TitleUsed = true;
        return lastH3;
      }
      return '';
    }
    return currentSectionTitle;
  };

  const countCard = () => {
    const title = nextCardTitle();
    if (title === '' && lastCountedSectionId === currentSectionId) return;
    cardCount += 1;
    lastCountedSectionId = currentSectionId;
  };

  const intro = String(frontmatter?.intro ?? '').trim();
  if (intro) countCard();

  let rehypeIgnoreDepth = 0;

  for (let i = 0; i < lines.length; i++) {
    const rawLine = lines[i];
    const line = normalizeLine(rawLine);

    if (isRehypeIgnoreStart(rawLine)) {
      rehypeIgnoreDepth++;
      continue;
    }
    if (isRehypeIgnoreEnd(rawLine)) {
      if (rehypeIgnoreDepth > 0) rehypeIgnoreDepth--;
      continue;
    }
    if (rehypeIgnoreDepth > 0) continue;

    if (!line.trim()) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;
    if (isHorizontalRuleLine(line)) continue;

    const setext = getSetextHeading(lines, i);
    if (setext) {
      if (setext.level === 1) {
        consumedDocHeading = true;
        resetHeadingState();
      } else {
        currentSectionTitle = cleanHeadingText(setext.text);
        currentSectionId = `s${sectionCount}`;
        sectionCount += 1;
        resetHeadingState();
      }
      i++;
      continue;
    }

    const h1 = /^#\s+(.+)$/.exec(line);
    if (h1) {
      const hText = cleanHeadingText(h1[1].trim());
      if (!consumedDocHeading) {
        consumedDocHeading = true;
        resetHeadingState();
        continue;
      }
      currentSectionTitle = hText;
      currentSectionId = `s${sectionCount}`;
      sectionCount += 1;
      resetHeadingState();
      continue;
    }

    const h2 = /^##\s+(.+)$/.exec(line);
    if (h2) {
      currentSectionTitle = cleanHeadingText(h2[1].trim());
      currentSectionId = `s${sectionCount}`;
      sectionCount += 1;
      resetHeadingState();
      continue;
    }

    const h3 = /^###\s+(.+)$/.exec(line);
    if (h3) {
      setH3(cleanHeadingText(h3[1].trim()));
      continue;
    }

    const h4 = /^####\s+(.+)$/.exec(line);
    if (h4) {
      setH4(cleanHeadingText(h4[1].trim()));
      continue;
    }

    const fence = parseFenceOpen(line);
    if (fence) {
      if (isHtmlPreviewFence(fence)) {
        i++;
        while (i < lines.length && !isFenceClose(stripHtmlCommentsInLine(lines[i]), fence.marker)) i++;
        continue;
      }

      const skipBetweenFences = (l) => {
        if (isRehypeIgnoreStart(l) || isRehypeIgnoreEnd(l)) return false;
        const cleaned = stripHtmlCommentsInLine(l);
        return !cleaned.trim()
          || /^\s*\{[.#][^}]+\}\s*$/.test(cleaned)
          || isHorizontalRuleLine(cleaned);
      };

      let hasFence = false;
      while (i < lines.length) {
        const openFence = parseFenceOpen(stripHtmlCommentsInLine(lines[i]));
        if (!openFence) break;
        if (isHtmlPreviewFence(openFence)) break;
        hasFence = true;

        i++;
        while (i < lines.length && !isFenceClose(stripHtmlCommentsInLine(lines[i]), openFence.marker)) i++;

        let j = i + 1;
        while (j < lines.length && skipBetweenFences(lines[j])) j++;
        const nextFence = j < lines.length ? parseFenceOpen(stripHtmlCommentsInLine(lines[j])) : undefined;
        if (!nextFence || isHtmlPreviewFence(nextFence)) break;
        i = j;
      }

      if (hasFence) countCard();
      continue;
    }

    if (line.includes('|') && i + 1 < lines.length && isTableSeparatorLine(lines[i + 1])) {
      i += 2;
      while (i < lines.length) {
        const rowLine = normalizeLine(lines[i]);
        if (!rowLine.trim() || !rowLine.includes('|')) break;
        i++;
      }
      i--;
      countCard();
      continue;
    }

    if (isListItem(line)) {
      let hasItem = false;
      while (i < lines.length) {
        const itemLine = normalizeLine(lines[i]);
        if (!isListItem(itemLine)) break;
        const itemText = stripListMarker(itemLine);
        if (itemText) hasItem = true;
        i++;
      }
      i--;
      if (hasItem) countCard();
      continue;
    }

    // paragraph (including multi-line paragraphs)
    if (line.trim()) {
      i++;
      while (i < lines.length) {
        const nextLine = normalizeLine(lines[i]);
        if (!nextLine.trim()) break;
        if (getSetextHeading(lines, i)) break;
        if (/^#{1,6}\s+/.test(nextLine)) break;
        if (isListItem(nextLine)) break;
        if (parseFenceOpen(nextLine)) break;
        if (isHorizontalRuleLine(nextLine)) break;
        i++;
      }
      i--;
      countCard();
      continue;
    }
  }

  return { sectionCount, cardCount };
}

function requestOrigin(req) {
  const forced = String(PUBLIC_ORIGIN ?? '').trim();
  if (forced) return forced.replace(/\/+$/g, '');

  const proto = String(req.headers['x-forwarded-proto'] ?? '').split(',')[0].trim();
  const host = String(req.headers['x-forwarded-host'] ?? req.headers.host ?? '').split(',')[0].trim();
  if (!host) return '';
  const scheme = proto || 'http';
  return `${scheme}://${host}`;
}

function json(res, statusCode, data, headers) {
  const body = JSON.stringify(data, null, 2);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
    ...headers,
  });
  res.end(body);
}

function text(res, statusCode, body, headers) {
  res.writeHead(statusCode, {
    'Content-Type': 'text/plain; charset=utf-8',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
    ...headers,
  });
  res.end(String(body ?? ''));
}

function contentTypeForPath(p) {
  const ext = path.extname(p).toLowerCase();
  if (ext === '.md' || ext === '.markdown') return 'text/markdown; charset=utf-8';
  if (ext === '.json') return 'application/json; charset=utf-8';
  if (ext === '.html') return 'text/html; charset=utf-8';
  if (ext === '.css') return 'text/css; charset=utf-8';
  if (ext === '.js' || ext === '.mjs') return 'application/javascript; charset=utf-8';
  if (ext === '.svg') return 'image/svg+xml';
  if (ext === '.png') return 'image/png';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  if (ext === '.webp') return 'image/webp';
  return 'application/octet-stream';
}

function isPathInsideDir(rootAbs, fileAbs) {
  const rel = path.relative(rootAbs, fileAbs);
  if (!rel) return true;
  return !rel.startsWith('..') && !path.isAbsolute(rel);
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

function listSvgIconIds(dirAbs) {
  return fs.readdir(dirAbs, { withFileTypes: true }).then(
    (entries) => {
      const out = new Set();
      for (const e of entries) {
        if (!e?.isFile?.()) continue;
        const name = String(e.name ?? '');
        if (!name.toLowerCase().endsWith('.svg')) continue;
        const base = name.slice(0, -'.svg'.length);
        if (base) out.add(base);
      }
      return out;
    },
    () => new Set(),
  );
}

const catalogCache = {
  version: 1,
  builtAt: 0,
  itemsByLang: new Map(),
};

function ensureCatalogBuilt() {
  if (catalogCache.builtAt > 0) return Promise.resolve();

  return Promise.resolve()
    .then(() => fs.stat(MDS_DIR))
    .then(
      () => true,
      (e) => Promise.reject(new Error(`Missing mds dir: ${MDS_DIR} (${String(e)})`)),
    )
    .then(() => {
      const langs = ['zh', 'en'];
      const iconSetByLang = new Map();
      return Promise.all(
        langs.map((lang) => {
          const langDir = path.join(MDS_DIR, lang);
          const iconDir = path.join(DEFAULT_REFERENCE_ICONS_DIR, lang);
          return fs.stat(langDir).then(
            (s) => (s?.isDirectory() ? langDir : undefined),
            () => undefined,
          ).then((dir) => {
            if (!dir) {
              catalogCache.itemsByLang.set(lang, []);
              return true;
            }
            return Promise.all([
              iconSetByLang.has(lang)
                ? Promise.resolve(iconSetByLang.get(lang))
                : listSvgIconIds(iconDir).then((set) => {
                  iconSetByLang.set(lang, set);
                  return set;
                }),
              walkMarkdownFiles(dir, dir),
            ]).then(([iconIds, rels]) => {
              return Promise.all(
                rels.map((rel) => {
                  const abs = path.join(dir, rel);
                  return fs.stat(abs).then((st) => {
                    const fallbackId = safeIdFromPath(rel);
                    return fs.readFile(abs, 'utf8').then(
                      (md) => {
                        const meta = extractDocNameAndTitle(md, fallbackId);
                        const counts = countSectionsAndCards(meta.frontmatter, meta.body, lang, false);
                        const hasIcon = iconIds instanceof Set ? iconIds.has(fallbackId) : false;
                        const icon = hasIcon ? `reference/icons/${lang}/${fallbackId}.svg` : '';
                        return {
                          id: `cloud_${fallbackId}`,
                          lang,
                          relPath: `${lang}/${rel}`.replace(/\\/g, '/'),
                          mdPath: `/mds/${lang}/${rel}`.replace(/\\/g, '/'),
                          name: meta.name || fallbackId,
                          title: meta.title || meta.name || fallbackId,
                          icon,
                          sectionCount: counts.sectionCount,
                          cardCount: counts.cardCount,
                          size: st.size,
                          mtimeMs: st.mtimeMs,
                        };
                      },
                      () => ({
                        id: `cloud_${fallbackId}`,
                        lang,
                        relPath: `${lang}/${rel}`.replace(/\\/g, '/'),
                        mdPath: `/mds/${lang}/${rel}`.replace(/\\/g, '/'),
                        name: fallbackId,
                        title: fallbackId,
                        icon: '',
                        sectionCount: 0,
                        cardCount: 0,
                        size: st.size,
                        mtimeMs: st.mtimeMs,
                      }),
                    );
                  });
                }),
              ).then((items) => {
                items.sort((a, b) => String(a.relPath).localeCompare(String(b.relPath)));
                catalogCache.itemsByLang.set(lang, items);
                return true;
              });
            });
          });
        }),
      ).then(() => {
        catalogCache.builtAt = Date.now();
      });
    });
}

function handleCatalog(req, res, url) {
  const lang = String(url.searchParams.get('lang') ?? '').trim().toLowerCase();
  const pickLang = lang === 'zh' || lang === 'en' ? lang : 'all';
  const origin = requestOrigin(req);

  const withUrl = (item) => ({
    id: item.id,
    lang: item.lang,
    relPath: item.relPath,
    mdUrl: origin ? `${origin}${item.mdPath}` : item.mdPath,
    name: item.name,
    title: item.title,
    icon: item.icon,
    sectionCount: Number(item.sectionCount ?? 0),
    cardCount: Number(item.cardCount ?? 0),
    size: item.size,
    mtimeMs: item.mtimeMs,
    mtimeIso: formatIso(item.mtimeMs),
  });

  const outItems = [];
  if (pickLang === 'all') {
    const zh = catalogCache.itemsByLang.get('zh') ?? [];
    const en = catalogCache.itemsByLang.get('en') ?? [];
    for (const it of zh) outItems.push(withUrl(it));
    for (const it of en) outItems.push(withUrl(it));
  } else {
    const items = catalogCache.itemsByLang.get(pickLang) ?? [];
    for (const it of items) outItems.push(withUrl(it));
  }

  return json(res, 200, {
    version: catalogCache.version,
    builtAt: catalogCache.builtAt ? formatIso(catalogCache.builtAt) : '',
    mdsDir: MDS_DIR,
    items: outItems,
  });
}

function handleMds(req, res, url) {
  const prefix = '/mds/';
  const rawPath = url.pathname || '/';
  if (!rawPath.startsWith(prefix)) return false;

  const rel = rawPath.slice(prefix.length);
  const abs = path.resolve(path.join(MDS_DIR, rel));
  if (!isPathInsideDir(MDS_DIR, abs)) {
    text(res, 403, 'Forbidden');
    return true;
  }

  Promise.resolve()
    .then(() => fs.stat(abs))
    .then(
      (st) => {
        if (!st?.isFile()) {
          text(res, 404, 'Not found');
          return;
        }
        res.writeHead(200, {
          'Content-Type': contentTypeForPath(abs),
          'Cache-Control': 'public, max-age=86400',
          'Access-Control-Allow-Origin': '*',
        });
        const stream = createReadStream(abs);
        stream.on('error', () => {
          if (!res.headersSent) text(res, 500, 'Read error');
          else res.end();
        });
        stream.pipe(res);
      },
      () => text(res, 404, 'Not found'),
    );
  return true;
}

function handleHealth(_req, res, url) {
  if (url.pathname !== '/api/health') return false;
  return json(res, 200, { ok: true });
}

function handleCorsPreflight(req, res) {
  if (req.method !== 'OPTIONS') return false;
  res.writeHead(204, {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '600',
  });
  res.end();
  return true;
}

async function ensureDir(dir) {
  await fs.mkdir(dir, { recursive: true });
}

function safeShareId(id) {
  const s = String(id ?? '').trim();
  const cleaned = s.replace(/[^A-Za-z0-9_-]/g, '').slice(0, 64);
  return cleaned;
}

function randomShareId() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
  let out = '';
  for (let i = 0; i < 10; i++) {
    out += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return out;
}

function readJsonBody(req, limitBytes = 512 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let total = 0;
    req.on('data', (chunk) => {
      const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      total += buf.length;
      if (total > limitBytes) {
        reject(new Error('Body too large'));
        req.destroy();
        return;
      }
      chunks.push(buf);
    });
    req.on('end', () => {
      try {
        const textBody = Buffer.concat(chunks).toString('utf-8');
        resolve(textBody ? JSON.parse(textBody) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

async function writeShareFile(id, data) {
  await ensureDir(SHARES_DIR);
  const safeId = safeShareId(id) || randomShareId();
  const filePath = path.join(SHARES_DIR, `${safeId}.json`);
  const payload = {
    id: safeId,
    createdAt: new Date().toISOString(),
    data: String(data ?? ''),
  };
  await fs.writeFile(filePath, JSON.stringify(payload, null, 2), 'utf-8');
  return safeId;
}

async function readShareFile(id) {
  const safeId = safeShareId(id);
  if (!safeId) return null;
  const filePath = path.join(SHARES_DIR, `${safeId}.json`);
  const raw = await fs.readFile(filePath, 'utf-8');
  const parsed = JSON.parse(raw);
  if (!parsed || String(parsed.id ?? '') !== safeId) return null;
  return parsed;
}

async function handleShareApi(req, res, url) {
  if (url.pathname === '/api/v1/share' && req.method === 'POST') {
    try {
      const body = await readJsonBody(req);
      const data = String(body?.data ?? '');
      if (!data.trim()) {
        return json(res, 400, { error: 'Missing data' });
      }
      const id = await writeShareFile(randomShareId(), data);
      const origin = requestOrigin(req) || 'http://localhost';
      return json(res, 200, {
        id,
        url: `${origin}/share/${encodeURIComponent(id)}`,
        deepLink: `refhm://share/${encodeURIComponent(id)}`,
      });
    } catch (e) {
      return json(res, 500, { error: String(e) });
    }
  }

  const getMatch = /^\/api\/v1\/share\/([^/]+)$/.exec(url.pathname);
  if (getMatch && req.method === 'GET') {
    try {
      const id = decodeURIComponent(getMatch[1]);
      const doc = await readShareFile(id);
      if (!doc) return json(res, 404, { error: 'Not found' });
      return json(res, 200, { id: doc.id, data: doc.data });
    } catch (e) {
      return json(res, 500, { error: String(e) });
    }
  }

  const pageMatch = /^\/share\/([^/]+)$/.exec(url.pathname);
  if (pageMatch && req.method === 'GET') {
    const id = decodeURIComponent(pageMatch[1]);
    return text(res, 200, `Share ID: ${id}\n\nOpen this link in the app to import.\n`);
  }

  return false;
}

const server = http.createServer((req, res) => {
  if (handleCorsPreflight(req, res)) return;

  const base = requestOrigin(req) || 'http://localhost';
  const url = new URL(req.url || '/', base);

  if (handleShareApi(req, res, url)) return;

  if (url.pathname === '/api/v1/catalog' && req.method === 'GET') {
    return ensureCatalogBuilt().then(
      () => handleCatalog(req, res, url),
      (e) => json(res, 500, { error: String(e) }),
    );
  }

  if (handleHealth(req, res, url)) return;
  if (handleMds(req, res, url)) return;

  if (url.pathname === '/' && req.method === 'GET') {
    return text(res, 200, 'reference-harmony online server');
  }

  return text(res, 404, 'Not found');
});

function uniquePorts(ports) {
  const out = [];
  const seen = new Set();
  for (const p of ports) {
    if (!Number.isFinite(p) || p <= 0) continue;
    if (seen.has(p)) continue;
    seen.add(p);
    out.push(p);
  }
  return out;
}

function startListenWithFallback(preferredPort) {
  const candidates = uniquePorts([preferredPort, 5181, 5182, 5183]);
  let started = false;

  const tryListen = (index) => {
    const port = candidates[index];
    if (!port) {
      // eslint-disable-next-line no-console
      console.error(`[online-server] failed to listen: no available port in ${candidates.join(', ')}`);
      process.exitCode = 1;
      return;
    }

    server.once('error', (e) => {
      if (started || server.listening) {
        return;
      }
      if (e && e.code === 'EADDRINUSE' && index + 1 < candidates.length) {
        // eslint-disable-next-line no-console
        console.warn(`[online-server] port ${port} in use, retrying on ${candidates[index + 1]}...`);
        tryListen(index + 1);
        return;
      }

      // eslint-disable-next-line no-console
      console.error(`[online-server] listen error on port ${port}: ${String(e)}`);
      process.exitCode = 1;
    });

    server.listen({ port, host: '0.0.0.0' }, () => {
      started = true;
      // eslint-disable-next-line no-console
      console.log(`[online-server] listening on http://localhost:${port}`);
      // eslint-disable-next-line no-console
      console.log(`[online-server] mds dir: ${MDS_DIR}`);
      if (port !== preferredPort) {
        // eslint-disable-next-line no-console
        console.log(`[online-server] note: preferred PORT=${preferredPort} was unavailable, using PORT=${port}`);
      }
    });
  };

  tryListen(0);
}

startListenWithFallback(PORT);
