import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';

const PORT = Number(process.env.MOCK_OPENWEBUI_PORT ?? 4173);
const HOST = process.env.MOCK_OPENWEBUI_HOST ?? '127.0.0.1';

const fixturesDir = path.resolve(process.cwd(), 'tests/fixtures');

const logInfo = message => {
  process.stdout.write(`${message}\n`);
};

const baseHtml = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Mock OpenWebUI</title>
    <style>
      body { font-family: sans-serif; margin: 2rem; }
      textarea { width: 100%; height: 120px; }
      .message-log { margin-top: 1rem; padding: 1rem; border: 1px solid #ccc; min-height: 80px; }
      .upload-area { margin-top: 1rem; border: 1px dashed #888; padding: 1rem; }
      button { margin-right: 0.5rem; }
    </style>
    <script>
      window.addEventListener('DOMContentLoaded', () => {
        const log = document.querySelector('.message-log');
        const textarea = document.querySelector('textarea');
        document.querySelector('#sendBtn').addEventListener('click', () => {
          const text = textarea.value.trim() || 'Hello from mock AI';
          log.innerHTML +=
            '<div class="message assistant">' + text + ' — источник: mock.pdf</div>';
          fetch('/api/chat', {
            method: 'POST',
            body: JSON.stringify({ message: text }),
          });
        });
        document.querySelector('#toggleSearch').addEventListener('change', event => {
          const enabled = event.target.checked;
          log.innerHTML +=
            '<div class="message">Web search ' + (enabled ? 'enabled' : 'disabled') + '</div>';
        });
        document.querySelector('#files').addEventListener('change', event => {
          log.innerHTML +=
            '<div class="message">Uploaded ' + event.target.files.length + ' file(s)</div>';
        });
      });
    </script>
  </head>
  <body>
    <h1>Mock OpenWebUI</h1>
    <section class="upload-area">
      <label for="files">Uploads</label>
      <input id="files" type="file" multiple />
      <button id="uploadBtn" aria-label="upload">Upload</button>
    </section>
    <section>
      <label>
        <input id="toggleSearch" type="checkbox" name="web_search" /> Web Search
      </label>
    </section>
    <section>
      <textarea placeholder="Message the AI..."></textarea>
      <div>
        <button id="sendBtn" type="submit">Send</button>
        <button aria-label="Settings">Settings</button>
      </div>
    </section>
    <div class="message-log" data-testid="assistant-message">
      <div class="message">Mock assistant ready.</div>
    </div>
  </body>
</html>`;

const server = http.createServer(async (req, res) => {
  if (!req.url) {
    res.writeHead(400);
    res.end('Bad request');
    return;
  }

  if (req.url.startsWith('/health')) {
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ status: 'ok', service: 'mock-openwebui' }));
    return;
  }

  if (req.url.startsWith('/fixtures/')) {
    const relative = req.url.replace('/fixtures/', '');
    const safePath = path.normalize(relative).replace(/^\.\//, '');
    if (safePath.includes('..')) {
      res.writeHead(400);
      res.end('Invalid fixture path');
      return;
    }
    try {
      // safePath проходит нормализацию, поэтому отключаем предупреждение security плагина
      // eslint-disable-next-line security/detect-non-literal-fs-filename
      const file = await readFile(path.join(fixturesDir, safePath));
      res.writeHead(200);
      res.end(file);
    } catch {
      res.writeHead(404);
      res.end('Not found');
    }
    return;
  }

  if (req.method === 'POST' && req.url.startsWith('/api/chat')) {
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ answer: 'Mock response with источник: mock.pdf' }));
    return;
  }

  res.setHeader('content-type', 'text/html; charset=utf-8');
  res.end(baseHtml);
});

export function startMockOpenWebUIServer() {
  return new Promise(resolve => {
    const listener = server.listen(PORT, HOST, () => {
      logInfo(`🧪 Mock OpenWebUI listening on http://${HOST}:${PORT}`);
      resolve(listener);
    });
  });
}

export function stopMockOpenWebUIServer() {
  return new Promise(resolve => {
    server.close(() => resolve(undefined));
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  startMockOpenWebUIServer();

  const handle = () => {
    stopMockOpenWebUIServer()
      .then(() => process.exit(0))
      .catch(() => process.exit(1));
  };
  process.on('SIGINT', handle);
  process.on('SIGTERM', handle);
}
