import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, type Plugin } from 'vite';
import vue from '@vitejs/plugin-vue';

function serveRepoStatic(): Plugin {
  const webRoot = path.dirname(fileURLToPath(import.meta.url));
  const repoRoot = path.resolve(webRoot, '..', '..');

  const mdsDir = path.join(repoRoot, 'mds');
  const iconsDir = path.join(repoRoot, 'entry', 'src', 'main', 'resources', 'rawfile', 'reference', 'icons');

  function safeResolve(baseDir: string, requestPath: string): string | undefined {
    const rel = String(requestPath ?? '').replace(/^\/+/, '');
    const abs = path.resolve(baseDir, rel);
    const base = path.resolve(baseDir);
    if (abs === base) return abs;
    if (!abs.startsWith(base + path.sep)) return undefined;
    return abs;
  }

  function contentType(filePath: string): string {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.svg') return 'image/svg+xml; charset=utf-8';
    if (ext === '.md' || ext === '.markdown') return 'text/markdown; charset=utf-8';
    if (ext === '.json') return 'application/json; charset=utf-8';
    if (ext === '.txt') return 'text/plain; charset=utf-8';
    return 'application/octet-stream';
  }

  function serveFile(res: any, filePath: string, method: string): void {
    res.statusCode = 200;
    res.setHeader('Content-Type', contentType(filePath));
    res.setHeader('Cache-Control', 'no-cache');
    if (method === 'HEAD') {
      res.end();
      return;
    }
    fs.createReadStream(filePath).pipe(res);
  }

  function notFound(res: any): void {
    res.statusCode = 404;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.end('Not Found');
  }

  return {
    name: 'serve-repo-static',
    apply: 'serve',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const method = String(req.method ?? 'GET').toUpperCase();
        if (method !== 'GET' && method !== 'HEAD') return next();

        const url = String(req.url ?? '');
        const pathname = url.split('?')[0] ?? '';

        if (pathname.startsWith('/reference/icons/')) {
          const rel = pathname.slice('/reference/icons/'.length);
          const filePath = safeResolve(iconsDir, rel);
          if (!filePath) return notFound(res);
          try {
            const st = fs.statSync(filePath);
            if (!st.isFile()) return notFound(res);
            return serveFile(res, filePath, method);
          } catch {
            return notFound(res);
          }
        }

        if (pathname.startsWith('/mds/')) {
          const rel = pathname.slice('/mds/'.length);
          const filePath = safeResolve(mdsDir, rel);
          if (!filePath) return notFound(res);
          try {
            const st = fs.statSync(filePath);
            if (!st.isFile()) return notFound(res);
            return serveFile(res, filePath, method);
          } catch {
            return notFound(res);
          }
        }

        return next();
      });
    },
  };
}

export default defineConfig({
  base: './',
  plugins: [serveRepoStatic(), vue()],
  server: {
    port: 5178,
  },
});
