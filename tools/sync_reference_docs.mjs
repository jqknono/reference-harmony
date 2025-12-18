#!/usr/bin/env node
/**
 * 同步 Quick Reference 文档（中英双语）并生成 App 可读的 JSON 到:
 *   entry/src/main/resources/rawfile/reference/{zh|en}/
 *
 * 用法:
 *   node tools/sync_reference_docs.mjs
 *   node tools/sync_reference_docs.mjs --langs=zh,en --limit=20
 *   node tools/sync_reference_docs.mjs --langs=en --en-ref=main --limit=50
 *   node tools/sync_reference_docs.mjs --mode=local   # 强制从 submodules 读取
 *   node tools/sync_reference_docs.mjs --mode=github  # 强制走 GitHub API
 *
 * 数据源:
 * - zh: https://github.com/jaywcjlove/reference/tree/main/docs
 * - en: https://github.com/Fechin/reference/tree/main/source/_posts
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const SOURCES = {
  zh: { repo: 'jaywcjlove/reference', docsDir: 'docs', submoduleDir: 'submodules/jaywcjlove-reference' },
  en: { repo: 'Fechin/reference', docsDir: 'source/_posts', submoduleDir: 'submodules/fechin-reference' },
};

function parseArgs(argv) {
  /** @type {{ zhRef: string; enRef: string; langs: string[]; mode: 'auto'|'local'|'github'; limit?: number; concurrency?: number; filter?: string }} */
  const out = { zhRef: 'main', enRef: 'main', langs: ['zh', 'en'], mode: 'auto', limit: undefined, concurrency: 8, filter: undefined };
  for (const arg of argv) {
    if (arg.startsWith('--ref=')) out.zhRef = arg.slice('--ref='.length); // backwards-compatible
    if (arg.startsWith('--zh-ref=')) out.zhRef = arg.slice('--zh-ref='.length);
    if (arg.startsWith('--en-ref=')) out.enRef = arg.slice('--en-ref='.length);
    if (arg.startsWith('--langs=')) out.langs = arg.slice('--langs='.length).split(',').map((s) => s.trim()).filter(Boolean);
    if (arg.startsWith('--mode=')) out.mode = /** @type {any} */ (arg.slice('--mode='.length));
    if (arg.startsWith('--limit=')) out.limit = Number(arg.slice('--limit='.length));
    if (arg.startsWith('--concurrency=')) out.concurrency = Number(arg.slice('--concurrency='.length));
    if (arg.startsWith('--filter=')) out.filter = arg.slice('--filter='.length).trim();
  }
  return out;
}

function cleanHeadingText(text) {
  // e.g. "1Password app {.row-span-2}" -> "1Password app"
  return text.replace(/\s*\{[^}]*\}\s*$/, '').trim();
}

function isTableSeparatorLine(line) {
  // | --- | :---: | ---: |
  const trimmed = line.trim();
  if (!trimmed.includes('|')) return false;

  // Fast-path reject: real separator rows contain only pipes, colons, dashes and whitespace.
  if (/[^|\s:-]/.test(trimmed)) return false;

  const cells = splitTableRow(trimmed);
  if (cells.length === 0) return false;
  for (const cell of cells) {
    const c = cell.replace(/\s+/g, '');
    if (!/^:?-{3,}:?$/.test(c)) return false;
  }
  return true;
}

function splitTableRow(line) {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|')) s = s.slice(0, -1);
  return s.split('|').map((c) => c.trim());
}

function isListItem(line) {
  return /^\s*([-*+]|(\d+\.))\s+/.test(line);
}

function stripListMarker(line) {
  return line.replace(/^\s*([-*+]|(\d+\.))\s+/, '').trim();
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function parseFenceOpen(line) {
  // Support ```lang, ~~~lang, and indented fences.
  const m = /^\s*(`{3,}|~{3,})([A-Za-z0-9_+.-]+)?\s*$/.exec(line);
  if (!m) return undefined;
  return { marker: m[1], lang: (m[2] ?? '').trim() };
}

function isFenceClose(line, marker) {
  return line.trim() === marker;
}

function isHorizontalRuleLine(line) {
  const t = (line ?? '').trim();
  if (!t) return false;
  return /^(-{3,}|\*{3,}|_{3,})$/.test(t);
}

function isSetextUnderline(line, ch) {
  const t = line.trim();
  if (!t) return false;
  if (ch) return new RegExp(`^${escapeRegExp(ch)}{3,}$`).test(t);
  return /^={3,}$/.test(t) || /^-{3,}$/.test(t);
}

function getSetextHeading(lines, i) {
  if (i + 1 >= lines.length) return undefined;
  const text = (lines[i] ?? '').trim();
  if (!text) return undefined;
  const underline = (lines[i + 1] ?? '').trim();
  if (isSetextUnderline(underline, '=')) return { level: 1, text };
  if (isSetextUnderline(underline, '-')) return { level: 2, text };
  return undefined;
}

function extractFrontmatter(markdown) {
  const normalized = markdown.replace(/\r\n/g, '\n');
  if (!normalized.startsWith('---\n')) return { frontmatter: {}, body: normalized };
  const end = normalized.indexOf('\n---\n', 4);
  if (end === -1) return { frontmatter: {}, body: normalized };
  const block = normalized.slice(4, end);
  const body = normalized.slice(end + '\n---\n'.length);

  /** @type {{ title?: string; intro?: string; icon?: string; background?: string }} */
  const frontmatter = {};
  const lines = block.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const m = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
    if (!m) continue;
    const key = m[1];
    const rawValue = (m[2] ?? '').trim();

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

    if (key === 'icon') {
      frontmatter.icon = rawValue.replace(/^['"]|['"]$/g, '').trim();
    }

    if (key === 'background') {
      frontmatter.background = rawValue.replace(/^['"]|['"]$/g, '').trim();
    }
  }

  return { frontmatter, body };
}

function safeIdFromPath(relativePath) {
  const raw = relativePath.replace(/\.md$/i, '').replace(/[\\/]/g, '_');
  const normalized = raw.normalize('NFKD').replace(/[^\w-]/g, '_');
  return normalized.replace(/_+/g, '_').replace(/^_+|_+$/g, '') || 'doc';
}

function extractDocNameAndTitle(frontmatter, body, { id, lang }) {
  const lines = body.replace(/\r\n/g, '\n').split('\n');

  const frontName = (frontmatter.title ?? '').trim();
  const frontIntro = (frontmatter.intro ?? '').trim();
  if (frontName) {
    return { name: frontName, title: frontIntro || frontName };
  }

  let name = id;
  let title = '';
  let h1Index = -1;
  let h1IsSetext = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;
    if (/^\s*<!--/.test(line)) continue;
    const fence = parseFenceOpen(line);
    if (fence) {
      i++;
      while (i < lines.length && !isFenceClose(lines[i], fence.marker)) i++;
      continue;
    }

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
    const line = lines[i];
    if (!line) continue;
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue;
    if (/^\s*<!--/.test(line)) continue;

    const fence = parseFenceOpen(line);
    if (fence) {
      i++;
      while (i < lines.length && !isFenceClose(lines[i], fence.marker)) i++;
      continue;
    }

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

function resolveIconUrl({ lang, id, ref }) {
  if (!id) return undefined;
  if (lang === 'zh') {
    return `https://raw.githubusercontent.com/${SOURCES.zh.repo}/${ref}/assets/${id}.svg`;
  }
  return `https://raw.githubusercontent.com/${SOURCES.en.repo}/${ref}/source/assets/icon/${id}.svg`;
}

function parseMarkdownToCards(markdown, { id, lang, mode, source, sourcePath, ref, debug }) {
  const { frontmatter, body } = extractFrontmatter(markdown);
  const lines = body.replace(/\r\n/g, '\n').split('\n');

  const meta = extractDocNameAndTitle(frontmatter, body, { id, lang });
  const icon = resolveIconUrl({ lang, id, ref });
  const title = meta.title;
  const name = meta.name;
  const introTitle = lang === 'en' ? 'Intro' : '简介';

  /** @type {{ id: string; title: string; startIndex: number }[]} */
  const sections = [{ id: 'intro', title: introTitle, startIndex: 0 }];
  /** @type {any[]} */
  const cards = [];

  let currentSectionId = 'intro';
  let currentSectionTitle = introTitle;
  let lastH3 = '';
  let lastH4 = '';
  let h3TitleUsed = false;
  let h4TitleUsed = false;
  let consumedDocHeading = false;

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

  const pushCard = (card) => {
    const allText = [
      card.title ?? '',
      card.body ?? '',
      card.front ?? '',
      card.back ?? '',
      card.code ?? '',
    ]
      .join('\n');

    const needsEncoding = allText.includes('"');
    if (!needsEncoding) {
      cards.push(card);
      return;
    }

    const encodeIfText = (s) => (typeof s === 'string' ? encodeURIComponent(s) : s);
    cards.push({
      ...card,
      encoded: true,
      title: encodeIfText(card.title),
      body: encodeIfText(card.body),
      front: encodeIfText(card.front),
      back: encodeIfText(card.back),
      code: encodeIfText(card.code),
    });
  };

  const intro = (frontmatter.intro ?? '').trim();
  if (intro) {
    pushCard({
      id: `${currentSectionId}-${cards.length}`,
      sectionId: currentSectionId,
      title: nextCardTitle(),
      kind: 'text',
      body: intro,
    });
  }

  const maxIterations = lines.length * 50 + 1000;
  let iter = 0;
  if (debug) console.log(`parse: ${lang}/${id} lines=${lines.length}`);

  for (let i = 0; i < lines.length; i++) {
    iter++;
    if (iter > maxIterations) {
      throw new Error(`解析超时：${lang}/${id} (iter=${iter} lines=${lines.length})`);
    }
    const line = lines[i];
    if (debug && i % 20 === 0) console.log(`... at ${lang}/${id} i=${i} ${line.trim().slice(0, 60)}`);
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue; // e.g. "{.shortcuts}"
    if (/^\s*<!--/.test(line)) continue;
    if (isHorizontalRuleLine(line)) continue;

    const setext = getSetextHeading(lines, i);
    if (setext) {
      if (setext.level === 1) {
        consumedDocHeading = true;
        resetHeadingState();
      } else {
        currentSectionTitle = cleanHeadingText(setext.text);
        currentSectionId = `s${sections.length}`;
        sections.push({ id: currentSectionId, title: currentSectionTitle, startIndex: cards.length });
        resetHeadingState();
      }
      i++; // skip underline
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
      // Some docs contain extra "# ..." headings for in-page anchors; treat them as section titles.
      currentSectionTitle = hText;
      currentSectionId = `s${sections.length}`;
      sections.push({ id: currentSectionId, title: currentSectionTitle, startIndex: cards.length });
      resetHeadingState();
      continue;
    }

    const h2 = /^##\s+(.+)$/.exec(line);
    if (h2) {
      currentSectionTitle = cleanHeadingText(h2[1].trim());
      currentSectionId = `s${sections.length}`;
      sections.push({ id: currentSectionId, title: currentSectionTitle, startIndex: cards.length });
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
      const codeParts = [];
      let codeLang = fence.lang;

      const skipBetweenFences = (l) =>
        !l.trim() || /^\s*\{[.#][^}]+\}\s*$/.test(l) || /^\s*<!--/.test(l) || isHorizontalRuleLine(l);

      while (i < lines.length) {
        const openFence = parseFenceOpen(lines[i]);
        if (!openFence) break;
        codeLang = codeLang || openFence.lang;
        const buf = [];
        i++; // move into fence body
        let fenceLines = 0;
        while (i < lines.length && !isFenceClose(lines[i], openFence.marker)) {
          buf.push(lines[i]);
          i++;
          fenceLines++;
          if (debug && fenceLines % 5000 === 0) console.log(`... fence ${lang}/${id} lines=${fenceLines}`);
        }
        const code = buf.join('\n').trimEnd();
        if (code) codeParts.push(code);

        let j = i + 1;
        while (j < lines.length && skipBetweenFences(lines[j])) j++;
        const nextFence = j < lines.length ? parseFenceOpen(lines[j]) : undefined;
        if (!nextFence) break;

        i = j;
      }

      const mergedCode = codeParts.join('\n\n').trimEnd();
      if (mergedCode) {
        pushCard({
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: nextCardTitle(),
          kind: 'code',
          lang: codeLang,
          code: mergedCode,
        });
      }
      continue;
    }

    // table (keep as a single card; do not split into front/back)
    if (line.includes('|') && i + 1 < lines.length && isTableSeparatorLine(lines[i + 1])) {
      const buf = [line.trimEnd(), lines[i + 1].trimEnd()];
      i += 2;
      let rows = 0;
      while (i < lines.length && lines[i].trim() && lines[i].includes('|')) {
        buf.push(lines[i].trimEnd());
        i++;
        rows++;
        if (debug && rows % 5000 === 0) console.log(`... table ${lang}/${id} rows=${rows}`);
      }
      if (debug) console.log(`table: ${lang}/${id} rows=${rows}`);
      i--;
      const body = buf.join('\n').trimEnd();
      if (body) {
        pushCard({
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: nextCardTitle(),
          kind: 'text',
          body,
        });
      }
      continue;
    }

    // list
    if (isListItem(line)) {
      const items = [];
      let listItems = 0;
      while (i < lines.length && isListItem(lines[i])) {
        items.push(`• ${stripListMarker(lines[i])}`);
        i++;
        listItems++;
        if (debug && listItems % 5000 === 0) console.log(`... list ${lang}/${id} items=${listItems}`);
      }
      i--;
      const text = items.join('\n').trim();
      if (text) {
        pushCard({
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: nextCardTitle(),
          kind: 'text',
          body: text,
        });
      }
      continue;
    }

    // paragraph
    if (line.trim()) {
      const buf = [line.trim()];
      i++;
      let paraLines = 1;
      while (i < lines.length && lines[i].trim()) {
        if (getSetextHeading(lines, i)) break;
        if (/^#{1,6}\s+/.test(lines[i])) break;
        if (isListItem(lines[i])) break;
        if (parseFenceOpen(lines[i])) break;
        if (isHorizontalRuleLine(lines[i])) break;
        if (!/^\s*\{[.#][^}]+\}\s*$/.test(lines[i])) buf.push(lines[i].trim());
        i++;
        paraLines++;
        if (debug && paraLines % 5000 === 0) console.log(`... paragraph ${lang}/${id} lines=${paraLines}`);
      }
      i--;
      const text = buf.join('\n').trim();
      if (text) {
        pushCard({
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: nextCardTitle(),
          kind: 'text',
          body: text,
        });
      }
    }
  }

  return {
    id,
    name,
    title,
    icon,
    sections,
    cards,
    source: {
      repo: `https://github.com/${source.repo}`,
      path: sourcePath,
      ref,
      url: `https://github.com/${source.repo}/tree/${ref}/${sourcePath}`,
      lang,
      mode,
    },
  };
}

async function githubJson(url) {
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'quickreference-sync',
      Accept: 'application/vnd.github+json',
    },
  });
  if (!res.ok) {
    const text = await res.text().then(
      (t) => t,
      () => '',
    );
    throw new Error(`GitHub API 失败:${res.status} ${res.statusText} ${text}`);
  }
  return res.json();
}

async function githubText(url) {
  const res = await fetch(url, { headers: { 'User-Agent': 'quickreference-sync' } });
  if (!res.ok) {
    throw new Error(`下载失败:${res.status} ${res.statusText} ${url}`);
  }
  return res.text();
}

async function pathExists(p) {
  return fs.access(p).then(
    () => true,
    () => false,
  );
}

async function listLocalMarkdownFiles(absDocsDir) {
  /** @type {{ relPath: string; absPath: string }[]} */
  const out = [];

  /** @type {Array<{ dir: string }>} */
  const queue = [{ dir: absDocsDir }];
  while (queue.length) {
    const { dir } = queue.shift();
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const e of entries) {
      const abs = path.join(dir, e.name);
      if (e.isDirectory()) {
        queue.push({ dir: abs });
      } else if (e.isFile() && e.name.toLowerCase().endsWith('.md')) {
        out.push({ relPath: path.relative(absDocsDir, abs), absPath: abs });
      }
    }
  }

  out.sort((a, b) => a.relPath.localeCompare(b.relPath));
  return out;
}

async function listMarkdownFiles({ repo, docsDir, ref }) {
  /** @type {{ path: string; download_url: string }[]} */
  const out = [];
  /** @type {{ path: string }[]} */
  const queue = [{ path: docsDir }];

  while (queue.length) {
    const item = queue.shift();
    const apiUrl = `https://api.github.com/repos/${repo}/contents/${item.path}?ref=${ref}`;
    const entries = await githubJson(apiUrl);
    for (const e of entries) {
      if (e.type === 'dir') queue.push({ path: e.path });
      if (e.type === 'file' && typeof e.name === 'string' && e.name.toLowerCase().endsWith('.md')) {
        out.push({ path: e.path, download_url: e.download_url });
      }
    }
  }

  out.sort((a, b) => a.path.localeCompare(b.path));
  return out;
}

async function mapWithConcurrency(items, concurrency, fn) {
  const limit = Number.isFinite(concurrency) && concurrency > 0 ? Math.floor(concurrency) : 8;
  const workers = Math.max(1, Math.min(limit, items.length));
  const results = new Array(items.length);
  let nextIndex = 0;

  await Promise.all(
    new Array(workers).fill(0).map(() =>
      Promise.resolve().then(async () => {
        while (true) {
          const idx = nextIndex;
          nextIndex++;
          if (idx >= items.length) return;
          results[idx] = await fn(items[idx], idx);
        }
      }),
    ),
  );

  return results;
}

async function main() {
  const { zhRef, enRef, langs, mode, limit, concurrency, filter } = parseArgs(process.argv.slice(2));
  const outDir = path.join(process.cwd(), 'entry', 'src', 'main', 'resources', 'rawfile', 'reference');
  await fs.mkdir(outDir, { recursive: true });

  /** @type {Map<'zh'|'en', any>} */
  const manifestsByLang = new Map();

  for (const lang of langs) {
    if (lang !== 'zh' && lang !== 'en') continue;
    const source = SOURCES[lang];
    const ref = lang === 'en' ? enRef : zhRef;
    console.log(`Syncing: ${lang} (ref=${ref} mode=${mode} concurrency=${concurrency ?? 8})`);
    const langOutDir = path.join(outDir, lang);
    await fs.mkdir(langOutDir, { recursive: true });

    /** @type {{ id: string; name: string; title: string; icon?: string; file: string; sectionCount: number; cardCount: number }[]} */
    const manifestDocs = [];

    const docsDirPrefix = `${source.docsDir.replace(/\\/g, '/')}/`;
    const absLocalDocsDir = path.join(process.cwd(), source.submoduleDir, source.docsDir);
    const localAvailable = await pathExists(absLocalDocsDir);
    const modeUsed = mode === 'github' ? 'github' : (mode === 'local' || (mode === 'auto' && localAvailable) ? 'local' : 'github');
    if (mode === 'local' && !localAvailable) {
      throw new Error(`未找到本地 submodule 文档目录: ${absLocalDocsDir}`);
    }

    if (modeUsed === 'local') {
      const docs = await listLocalMarkdownFiles(absLocalDocsDir);
      const filtered = filter ? docs.filter((d) => d.relPath.replace(/\\/g, '/').includes(filter)) : docs;
      const selected = typeof limit === 'number' ? filtered.slice(0, limit) : filtered;
      let done = 0;
      const summaries = await mapWithConcurrency(selected, concurrency ?? 8, async (doc) => {
        const rel = doc.relPath.replace(/\\/g, '/');
        const id = safeIdFromPath(rel);
        if (filter) console.log(`Processing: ${lang} ${id} (${rel})`);
        const md = await fs.readFile(doc.absPath, 'utf8');
        const sourcePath = `${source.docsDir.replace(/\\/g, '/')}/${rel}`;
        const parsed = parseMarkdownToCards(md, { id, lang, mode: modeUsed, source, sourcePath, ref, debug: Boolean(filter) });
        if (filter) console.log(`Parsed: ${lang} ${id} sections=${parsed.sections.length} cards=${parsed.cards.length}`);
        const file = `reference/${lang}/${id}.json`;

        await fs.writeFile(path.join(langOutDir, `${id}.json`), JSON.stringify(parsed, null, 2), 'utf8');
        if (filter) console.log(`Wrote: ${lang} ${id}`);
        done++;
        if (done % 50 === 0) console.log(`... ${lang} ${done}/${selected.length}`);
        return {
          id,
          name: parsed.name ?? parsed.title ?? id,
          title: parsed.title,
          icon: parsed.icon,
          file,
          sectionCount: parsed.sections.length,
          cardCount: parsed.cards.length,
        };
      });
      manifestDocs.push(...summaries.filter(Boolean));
    } else {
      const docs = await listMarkdownFiles({ repo: source.repo, docsDir: source.docsDir, ref });
      const filtered = filter ? docs.filter((d) => String(d.path ?? '').includes(filter)) : docs;
      const selected = typeof limit === 'number' ? filtered.slice(0, limit) : filtered;
      let done = 0;
      const summaries = await mapWithConcurrency(selected, Math.min(concurrency ?? 8, 4), async (doc) => {
        const rel = doc.path.replace(/\\/g, '/').startsWith(docsDirPrefix) ? doc.path.replace(/\\/g, '/').slice(docsDirPrefix.length) : doc.path;
        const id = safeIdFromPath(rel);
        if (filter) console.log(`Processing: ${lang} ${id} (${doc.path})`);
        const md = await githubText(doc.download_url);
        const parsed = parseMarkdownToCards(md, { id, lang, mode: modeUsed, source, sourcePath: doc.path, ref, debug: Boolean(filter) });
        if (filter) console.log(`Parsed: ${lang} ${id} sections=${parsed.sections.length} cards=${parsed.cards.length}`);
        const file = `reference/${lang}/${id}.json`;

        await fs.writeFile(path.join(langOutDir, `${id}.json`), JSON.stringify(parsed, null, 2), 'utf8');
        if (filter) console.log(`Wrote: ${lang} ${id}`);
        done++;
        if (done % 50 === 0) console.log(`... ${lang} ${done}/${selected.length}`);
        return {
          id,
          name: parsed.name ?? parsed.title ?? id,
          title: parsed.title,
          icon: parsed.icon,
          file,
          sectionCount: parsed.sections.length,
          cardCount: parsed.cards.length,
        };
      });
      manifestDocs.push(...summaries.filter(Boolean));
    }

    manifestDocs.sort((a, b) => a.name.localeCompare(b.name));
    const manifest = {
      source: {
        repo: `https://github.com/${source.repo}`,
        docsPath: source.docsDir,
        ref,
        lang,
        mode: modeUsed,
      },
      docs: manifestDocs,
    };

    await fs.writeFile(path.join(langOutDir, 'manifest.json'), JSON.stringify(manifest, null, 2), 'utf8');
    manifestsByLang.set(lang, manifest);
    console.log(`OK: ${lang} ${manifestDocs.length} docs -> ${langOutDir}`);
  }

  const manifestBundle = {
    zh: manifestsByLang.get('zh') ?? null,
    en: manifestsByLang.get('en') ?? null,
  };
  await fs.writeFile(path.join(outDir, 'manifest.json'), JSON.stringify(manifestBundle, null, 2), 'utf8');
  console.log(`OK: manifest bundle -> ${path.join(outDir, 'manifest.json')}`);
}

main().then(
  () => process.exit(0),
  (err) => {
    console.error(err);
    process.exit(1);
  },
);
