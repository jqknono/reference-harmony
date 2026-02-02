import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const WEB_ROOT = path.resolve(__dirname, '..');
const REPO_ROOT = path.resolve(WEB_ROOT, '..', '..');

const SRC_MDS_DIR = path.join(REPO_ROOT, 'mds');
const SRC_REFERENCE_ICONS_DIR = path.join(
  REPO_ROOT,
  'entry',
  'src',
  'main',
  'resources',
  'rawfile',
  'reference',
  'icons',
);
const DIST_DIR = path.join(WEB_ROOT, 'dist');
const DIST_MDS_DIR = path.join(DIST_DIR, 'mds');
const DIST_REFERENCE_ICONS_DIR = path.join(DIST_DIR, 'reference', 'icons');

await fs.stat(DIST_DIR).then(
  (s) => s?.isDirectory() ?? false,
  (e) => Promise.reject(new Error(`Missing dist dir: ${DIST_DIR} (${String(e)})`)),
);

await fs.rm(DIST_MDS_DIR, { recursive: true, force: true });
await fs.mkdir(DIST_MDS_DIR, { recursive: true });
await fs.cp(SRC_MDS_DIR, DIST_MDS_DIR, { recursive: true });

// eslint-disable-next-line no-console
console.log(`[online-web] copied mds -> ${path.relative(WEB_ROOT, DIST_MDS_DIR)}`);

await fs.rm(DIST_REFERENCE_ICONS_DIR, { recursive: true, force: true });
await fs.mkdir(path.dirname(DIST_REFERENCE_ICONS_DIR), { recursive: true });
await fs.cp(SRC_REFERENCE_ICONS_DIR, DIST_REFERENCE_ICONS_DIR, { recursive: true });

// eslint-disable-next-line no-console
console.log(`[online-web] copied icons -> ${path.relative(WEB_ROOT, DIST_REFERENCE_ICONS_DIR)}`);

