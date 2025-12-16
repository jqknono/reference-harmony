#!/usr/bin/env node
/**
 * 同步 https://github.com/jaywcjlove/reference 的 docs/ Markdown，
 * 预处理为 App 可读的卡片 JSON，输出到：
 *   entry/src/main/resources/rawfile/reference/
 *
 * 用法：
 *   node tools/sync_reference_docs.mjs
 *   node tools/sync_reference_docs.mjs --ref=main --limit=20
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

const REPO = 'jaywcjlove/reference';
const DOCS_DIR = 'docs';

function parseArgs(argv) {
  /** @type {{ ref: string; limit?: number }} */
  const out = { ref: 'main', limit: undefined };
  for (const arg of argv) {
    if (arg.startsWith('--ref=')) out.ref = arg.slice('--ref='.length);
    if (arg.startsWith('--limit=')) out.limit = Number(arg.slice('--limit='.length));
  }
  return out;
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

function parseMarkdownToCards(markdown, { id, sourcePath, ref }) {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');

  let title = id;
  /** @type {{ id: string; title: string; startIndex: number }[]} */
  const sections = [{ id: 'intro', title: '概览', startIndex: 0 }];
  /** @type {any[]} */
  const cards = [];

  let currentSectionId = 'intro';
  let currentSectionTitle = '概览';
  let lastH3 = '';

  const pushCard = (card) => {
    cards.push(card);
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    const h1 = /^#\s+(.+)$/.exec(line);
    if (h1) {
      title = h1[1].trim();
      lastH3 = '';
      continue;
    }

    const h2 = /^##\s+(.+)$/.exec(line);
    if (h2) {
      currentSectionTitle = h2[1].trim();
      currentSectionId = `s${sections.length}`;
      sections.push({ id: currentSectionId, title: currentSectionTitle, startIndex: cards.length });
      lastH3 = '';
      continue;
    }

    const h3 = /^###\s+(.+)$/.exec(line);
    if (h3) {
      lastH3 = h3[1].trim();
      continue;
    }

    const fence = /^```(\w+)?\s*$/.exec(line);
    if (fence) {
      const lang = (fence[1] ?? '').trim();
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
          lang,
          code,
        });
      }
      continue;
    }

    // table
    if (line.includes('|') && i + 1 < lines.length && isTableSeparatorLine(lines[i + 1])) {
      const header = splitTableRow(line);
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
      const body = items.join('\n').trim();
      if (body) {
        pushCard({
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: lastH3 || currentSectionTitle,
          kind: 'text',
          body,
        });
      }
      continue;
    }

    // paragraph
    if (line.trim()) {
      const buf = [line.trim()];
      i++;
      while (i < lines.length && lines[i].trim() && !/^#{1,6}\s+/.test(lines[i]) && !isListItem(lines[i]) && !/^```/.test(lines[i])) {
        buf.push(lines[i].trim());
        i++;
      }
      i--;
      const body = buf.join('\n').trim();
      if (body) {
        pushCard({
          id: `${currentSectionId}-${cards.length}`,
          sectionId: currentSectionId,
          title: lastH3 || currentSectionTitle,
          kind: 'text',
          body,
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
      repo: `https://github.com/${REPO}`,
      path: sourcePath,
      ref,
      url: `https://github.com/${REPO}/tree/${ref}/${sourcePath}`,
      generatedAt: new Date().toISOString(),
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
    throw new Error(`GitHub API 失败：${res.status} ${res.statusText} ${text}`);
  }
  return res.json();
}

async function githubText(url) {
  const res = await fetch(url, { headers: { 'User-Agent': 'quickreference-sync' } });
  if (!res.ok) {
    throw new Error(`下载失败：${res.status} ${res.statusText} ${url}`);
  }
  return res.text();
}

async function listDocs(ref) {
  /** @type {{ path: string; download_url: string }[]} */
  const out = [];
  /** @type {{ path: string }[]} */
  const queue = [{ path: DOCS_DIR }];

  while (queue.length) {
    const item = queue.shift();
    const apiUrl = `https://api.github.com/repos/${REPO}/contents/${item.path}?ref=${ref}`;
    const entries = await githubJson(apiUrl);
    for (const e of entries) {
      if (e.type === 'dir') queue.push({ path: e.path });
      if (e.type === 'file' && typeof e.name === 'string' && e.name.toLowerCase().endsWith('.md')) {
        out.push({ path: e.path, download_url: e.download_url });
      }
    }
  }
  return out;
}

async function main() {
  const { ref, limit } = parseArgs(process.argv.slice(2));
  const outDir = path.join(process.cwd(), 'entry', 'src', 'main', 'resources', 'rawfile', 'reference');
  await fs.mkdir(outDir, { recursive: true });

  const docs = await listDocs(ref);
  const selected = typeof limit === 'number' ? docs.slice(0, limit) : docs;

  /** @type {{ id: string; title: string; file: string; sectionCount: number; cardCount: number }[]} */
  const manifestDocs = [];

  for (const doc of selected) {
    const id = doc.path.replace(/^docs\//, '').replace(/\.md$/i, '').replace(/[\\/]/g, '_');
    const md = await githubText(doc.download_url);
    const parsed = parseMarkdownToCards(md, { id, sourcePath: doc.path, ref });
    const file = `reference/${id}.json`;

    await fs.writeFile(path.join(outDir, `${id}.json`), JSON.stringify(parsed, null, 2), 'utf8');
    manifestDocs.push({
      id,
      title: parsed.title,
      file,
      sectionCount: parsed.sections.length,
      cardCount: parsed.cards.length,
    });
  }

  manifestDocs.sort((a, b) => a.title.localeCompare(b.title));
  const manifest = {
    source: {
      repo: `https://github.com/${REPO}`,
      docsPath: DOCS_DIR,
      ref,
      generatedAt: new Date().toISOString(),
    },
    docs: manifestDocs,
  };

  await fs.writeFile(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2), 'utf8');
  console.log(`OK: 写入 ${manifestDocs.length} 个文档到 ${outDir}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
