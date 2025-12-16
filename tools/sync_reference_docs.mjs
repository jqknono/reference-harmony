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
  /** @type {{ zhRef: string; enRef: string; langs: string[]; mode: 'auto'|'local'|'github'; limit?: number }} */
  const out = { zhRef: 'main', enRef: 'main', langs: ['zh', 'en'], mode: 'auto', limit: undefined };
  for (const arg of argv) {
    if (arg.startsWith('--ref=')) out.zhRef = arg.slice('--ref='.length); // backwards-compatible
    if (arg.startsWith('--zh-ref=')) out.zhRef = arg.slice('--zh-ref='.length);
    if (arg.startsWith('--en-ref=')) out.enRef = arg.slice('--en-ref='.length);
    if (arg.startsWith('--langs=')) out.langs = arg.slice('--langs='.length).split(',').map((s) => s.trim()).filter(Boolean);
    if (arg.startsWith('--mode=')) out.mode = /** @type {any} */ (arg.slice('--mode='.length));
    if (arg.startsWith('--limit=')) out.limit = Number(arg.slice('--limit='.length));
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
  return /^(\|?\s*:?-{3,}:?\s*)+\|?$/.test(trimmed.replace(/\s+/g, ''));
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

function extractFrontmatter(markdown) {
  const normalized = markdown.replace(/\r\n/g, '\n');
  if (!normalized.startsWith('---\n')) return { frontmatter: {}, body: normalized };
  const end = normalized.indexOf('\n---\n', 4);
  if (end === -1) return { frontmatter: {}, body: normalized };
  const block = normalized.slice(4, end);
  const body = normalized.slice(end + '\n---\n'.length);

  /** @type {{ title?: string; intro?: string }} */
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
  }

  return { frontmatter, body };
}

function safeIdFromPath(relativePath) {
  const raw = relativePath.replace(/\.md$/i, '').replace(/[\\/]/g, '_');
  const normalized = raw.normalize('NFKD').replace(/[^\w-]/g, '_');
  return normalized.replace(/_+/g, '_').replace(/^_+|_+$/g, '') || 'doc';
}

function parseMarkdownToCards(markdown, { id, lang, mode, source, sourcePath, ref }) {
  const { frontmatter, body } = extractFrontmatter(markdown);
  const lines = body.replace(/\r\n/g, '\n').split('\n');

  let title = frontmatter.title?.trim() || id;
  const introTitle = lang === 'en' ? 'Intro' : '简介';

  /** @type {{ id: string; title: string; startIndex: number }[]} */
  const sections = [{ id: 'intro', title: introTitle, startIndex: 0 }];
  /** @type {any[]} */
  const cards = [];

  let currentSectionId = 'intro';
  let currentSectionTitle = introTitle;
  let lastH3 = '';

  const pushCard = (card) => {
    cards.push(card);
  };

  const intro = (frontmatter.intro ?? '').trim();
  if (intro) {
    pushCard({
      id: `${currentSectionId}-${cards.length}`,
      sectionId: currentSectionId,
      title: currentSectionTitle,
      kind: 'text',
      body: intro,
    });
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^\s*\{[.#][^}]+\}\s*$/.test(line)) continue; // e.g. "{.shortcuts}"
    if (/^\s*<!--/.test(line)) continue;

    const h1 = /^#\s+(.+)$/.exec(line);
    if (h1) {
      title = cleanHeadingText(h1[1].trim());
      lastH3 = '';
      continue;
    }

    const h2 = /^##\s+(.+)$/.exec(line);
    if (h2) {
      currentSectionTitle = cleanHeadingText(h2[1].trim());
      currentSectionId = `s${sections.length}`;
      sections.push({ id: currentSectionId, title: currentSectionTitle, startIndex: cards.length });
      lastH3 = '';
      continue;
    }

    const h3 = /^###\s+(.+)$/.exec(line);
    if (h3) {
      lastH3 = cleanHeadingText(h3[1].trim());
      continue;
    }

    const fence = /^```(\w+)?\s*$/.exec(line);
    if (fence) {
      const codeLang = (fence[1] ?? '').trim();
      const buf = [];
      i++;
      while (i < lines.length && !/^```/.test(lines[i])) {
        buf.push(lines[i]);
        i++;
      }
      const code = buf.join('\n').trimEnd();
      if (code) {
        pushCard({
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: lastH3 || currentSectionTitle,
          kind: 'code',
          lang: codeLang,
          code,
        });
      }
      continue;
    }

    // table
    if (line.includes('|') && i + 1 < lines.length && isTableSeparatorLine(lines[i + 1])) {
      i += 2;
      while (i < lines.length && lines[i].trim() && lines[i].includes('|')) {
        const cols = splitTableRow(lines[i]);
        if (cols.length >= 2) {
          const key = cols[0];
          const value = cols.slice(1).join(' | ').trim();
          if (key && value) {
            pushCard({
              id: `${currentSectionId}-${cards.length}`,
              sectionId: currentSectionId,
              title: lastH3 || currentSectionTitle,
              kind: 'qa',
              front: key,
              back: value,
            });
          }
        }
        i++;
      }
      i--;
      continue;
    }

    // list
    if (isListItem(line)) {
      const items = [];
      while (i < lines.length && isListItem(lines[i])) {
        items.push(`• ${stripListMarker(lines[i])}`);
        i++;
      }
      i--;
      const text = items.join('\n').trim();
      if (text) {
        pushCard({
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: lastH3 || currentSectionTitle,
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
      while (i < lines.length && lines[i].trim() && !/^#{1,6}\s+/.test(lines[i]) && !isListItem(lines[i]) && !/^```/.test(lines[i])) {
        if (!/^\s*\{[.#][^}]+\}\s*$/.test(lines[i])) buf.push(lines[i].trim());
        i++;
      }
      i--;
      const text = buf.join('\n').trim();
      if (text) {
        pushCard({
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: lastH3 || currentSectionTitle,
          kind: 'text',
          body: text,
        });
      }
    }
  }

  return {
    id,
    title,
    sections,
    cards,
    source: {
      repo: `https://github.com/${source.repo}`,
      path: sourcePath,
      ref,
      url: `https://github.com/${source.repo}/tree/${ref}/${sourcePath}`,
      generatedAt: new Date().toISOString(),
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
    const text = await res.text().catch(() => '');
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
  try {
    await fs.access(p);
    return true;
  } catch (_) {
    return false;
  }
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

async function main() {
  const { zhRef, enRef, langs, mode, limit } = parseArgs(process.argv.slice(2));
  const outDir = path.join(process.cwd(), 'entry', 'src', 'main', 'resources', 'rawfile', 'reference');
  await fs.mkdir(outDir, { recursive: true });

  /** @type {Map<'zh'|'en', any>} */
  const manifestsByLang = new Map();

  for (const lang of langs) {
    if (lang !== 'zh' && lang !== 'en') continue;
    const source = SOURCES[lang];
    const ref = lang === 'en' ? enRef : zhRef;
    const langOutDir = path.join(outDir, lang);
    await fs.mkdir(langOutDir, { recursive: true });

    /** @type {{ id: string; title: string; file: string; sectionCount: number; cardCount: number }[]} */
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
      const selected = typeof limit === 'number' ? docs.slice(0, limit) : docs;
      for (const doc of selected) {
        const rel = doc.relPath.replace(/\\/g, '/');
        const id = safeIdFromPath(rel);
        const md = await fs.readFile(doc.absPath, 'utf8');
        const sourcePath = `${source.docsDir.replace(/\\/g, '/')}/${rel}`;
        const parsed = parseMarkdownToCards(md, { id, lang, mode: modeUsed, source, sourcePath, ref });
        const file = `reference/${lang}/${id}.json`;

        await fs.writeFile(path.join(langOutDir, `${id}.json`), JSON.stringify(parsed, null, 2), 'utf8');
        manifestDocs.push({
          id,
          title: parsed.title,
          file,
          sectionCount: parsed.sections.length,
          cardCount: parsed.cards.length,
        });
      }
    } else {
      const docs = await listMarkdownFiles({ repo: source.repo, docsDir: source.docsDir, ref });
      const selected = typeof limit === 'number' ? docs.slice(0, limit) : docs;
      for (const doc of selected) {
        const rel = doc.path.replace(/\\/g, '/').startsWith(docsDirPrefix) ? doc.path.replace(/\\/g, '/').slice(docsDirPrefix.length) : doc.path;
        const id = safeIdFromPath(rel);
        const md = await githubText(doc.download_url);
        const parsed = parseMarkdownToCards(md, { id, lang, mode: modeUsed, source, sourcePath: doc.path, ref });
        const file = `reference/${lang}/${id}.json`;

        await fs.writeFile(path.join(langOutDir, `${id}.json`), JSON.stringify(parsed, null, 2), 'utf8');
        manifestDocs.push({
          id,
          title: parsed.title,
          file,
          sectionCount: parsed.sections.length,
          cardCount: parsed.cards.length,
        });
      }
    }

    manifestDocs.sort((a, b) => a.title.localeCompare(b.title));
    const manifest = {
      source: {
        repo: `https://github.com/${source.repo}`,
        docsPath: source.docsDir,
        ref,
        generatedAt: new Date().toISOString(),
        lang,
        mode: modeUsed,
      },
      docs: manifestDocs,
    };

    await fs.writeFile(path.join(langOutDir, 'manifest.json'), JSON.stringify(manifest, null, 2), 'utf8');
    manifestsByLang.set(lang, manifest);
    console.log(`OK: ${lang} ${manifestDocs.length} docs -> ${langOutDir}`);
  }

  // backward-compat: legacy single-language manifest location
  const legacyManifest = manifestsByLang.get('zh') ?? manifestsByLang.get('en');
  if (legacyManifest) {
    await fs.writeFile(path.join(outDir, 'manifest.json'), JSON.stringify(legacyManifest, null, 2), 'utf8');
    console.log(`OK: legacy manifest -> ${path.join(outDir, 'manifest.json')}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
