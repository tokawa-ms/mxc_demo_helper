const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const rootDirectory = __dirname;
const publicDirectory = path.join(rootDirectory, 'public');
const scriptPath = path.join(rootDirectory, 'scripts', 'invoke_mxc_demo_step.ps1');
const port = Number(process.env.PORT || 3000);
const host = process.env.HOST || '127.0.0.1';

const demos = [
  {
    id: 'preflight',
    title: 'Preflight',
    subtitle: 'wxc-exec.exe and Visual Studio environment check',
    kind: 'setup',
    risk: 'safe',
    summary: 'Verify that the built MXC executable can launch before running policy demos.'
  },
  {
    id: 'baseline-network',
    title: 'Baseline network',
    subtitle: 'Normal VM TCP reachability',
    kind: 'network',
    risk: 'safe',
    summary: 'Confirm that the host VM can reach www.msftconnecttest.com:80 outside MXC.'
  },
  {
    id: 'network-open',
    title: 'Network open',
    subtitle: 'internetClient capability',
    kind: 'network',
    risk: 'safe',
    summary: 'Run curl.exe inside MXC with internetClient and confirm outbound HTTP succeeds.'
  },
  {
    id: 'network-block',
    title: 'Network block',
    subtitle: 'defaultPolicy=block with firewall enforcement',
    kind: 'network',
    risk: 'admin',
    summary: 'Run curl.exe inside MXC and confirm outbound HTTP is blocked by the profile.'
  },
  {
    id: 'filesystem-setup',
    title: 'Filesystem setup',
    subtitle: 'Prepare allowed and readonly folders',
    kind: 'filesystem',
    risk: 'safe',
    summary: 'Create the demo folders and reset previous output files under C:\\mxc-demo-fs.'
  },
  {
    id: 'filesystem-readwrite',
    title: 'Filesystem read/write',
    subtitle: 'readwritePaths allows output creation',
    kind: 'filesystem',
    risk: 'safe',
    summary: 'Read input.txt and create output-from-mxc.txt under the allowed path.'
  },
  {
    id: 'filesystem-readonly',
    title: 'Filesystem readonly',
    subtitle: 'readonlyPaths denies writes',
    kind: 'filesystem',
    risk: 'safe',
    summary: 'Read both folders and confirm the write attempt under readonly is denied.'
  }
];

const contentTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml; charset=utf-8'
};

function sendJson(response, statusCode, value) {
  response.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store'
  });
  response.end(JSON.stringify(value, null, 2));
}

function sendNotFound(response) {
  sendJson(response, 404, { error: 'Not found' });
}

function safePublicPath(requestPath) {
  const normalizedPath = requestPath === '/' ? '/index.html' : requestPath;
  const decodedPath = decodeURIComponent(normalizedPath.split('?')[0]);
  const filePath = path.normalize(path.join(publicDirectory, decodedPath));
  if (!filePath.startsWith(publicDirectory)) {
    return null;
  }
  return filePath;
}

function serveStatic(request, response) {
  const filePath = safePublicPath(request.url || '/');
  if (!filePath) {
    sendNotFound(response);
    return;
  }

  fs.readFile(filePath, (error, content) => {
    if (error) {
      sendNotFound(response);
      return;
    }

    const contentType = contentTypes[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
    response.writeHead(200, {
      'content-type': contentType,
      'cache-control': 'no-store'
    });
    response.end(content);
  });
}

function requestAbort(response, onAbort) {
  response.on('close', () => {
    if (!response.writableEnded) {
      onAbort();
    }
  });
}

function runPowerShell(args, response) {
  response.writeHead(200, {
    'content-type': 'application/x-ndjson; charset=utf-8',
    'cache-control': 'no-store',
    connection: 'keep-alive'
  });

  const child = spawn('powershell.exe', [
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    scriptPath,
    ...args
  ], {
    cwd: rootDirectory,
    windowsHide: true,
    env: {
      ...process.env,
      PYTHONIOENCODING: 'utf-8'
    }
  });

  const writeEvent = (type, payload) => {
    response.write(JSON.stringify({ type, ...payload }) + '\n');
  };

  writeEvent('start', { at: new Date().toISOString() });

  const forward = (streamName, chunk) => {
    const text = chunk.toString('utf8');
    for (const line of text.replace(/\r\n/g, '\n').split('\n')) {
      if (line.length > 0) {
        writeEvent('log', { stream: streamName, line });
      }
    }
  };

  child.stdout.on('data', chunk => forward('stdout', chunk));
  child.stderr.on('data', chunk => forward('stderr', chunk));
  child.on('error', error => {
    writeEvent('error', { message: error.message });
  });
  child.on('close', code => {
    writeEvent('end', { code, ok: code === 0, at: new Date().toISOString() });
    response.end();
  });

  requestAbort(response, () => {
    if (!child.killed) {
      child.kill();
    }
  });
}

function collectJsonBody(request) {
  return new Promise(resolve => {
    let body = '';
    request.on('data', chunk => {
      body += chunk;
    });
    request.on('end', () => {
      if (!body) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(body));
      } catch {
        resolve({});
      }
    });
  });
}

function toPowerShellArgs(options) {
  const args = [];
  if (options.repoPath) {
    args.push('-RepoPath', String(options.repoPath));
  }
  if (options.configDirectory) {
    args.push('-ConfigDirectory', String(options.configDirectory));
  }
  if (options.vcVarsPath) {
    args.push('-VcVarsPath', String(options.vcVarsPath));
  }
  return args;
}

async function route(request, response) {
  const url = new URL(request.url || '/', `http://${request.headers.host || `${host}:${port}`}`);

  if (request.method === 'GET' && url.pathname === '/api/demos') {
    sendJson(response, 200, { demos });
    return;
  }

  if (request.method === 'POST' && url.pathname === '/api/status') {
    const body = await collectJsonBody(request);
    runPowerShell(['-StatusJson', ...toPowerShellArgs(body)], response);
    return;
  }

  if (request.method === 'POST' && url.pathname.startsWith('/api/run/')) {
    const demoId = decodeURIComponent(url.pathname.slice('/api/run/'.length));
    if (!demos.some(demo => demo.id === demoId)) {
      sendJson(response, 404, { error: `Unknown demo: ${demoId}` });
      return;
    }

    const body = await collectJsonBody(request);
    runPowerShell(['-Demo', demoId, ...toPowerShellArgs(body)], response);
    return;
  }

  if (request.method === 'GET') {
    serveStatic(request, response);
    return;
  }

  sendNotFound(response);
}

const server = http.createServer((request, response) => {
  route(request, response).catch(error => {
    sendJson(response, 500, { error: error.message });
  });
});

server.listen(port, host, () => {
  console.log(`MXC demo dashboard listening on http://${host}:${port}`);
});
