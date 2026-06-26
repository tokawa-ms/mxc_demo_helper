const demoGrid = document.querySelector('#demoGrid');
const logOutput = document.querySelector('#logOutput');
const refreshStatusButton = document.querySelector('#refreshStatus');
const runSafeFlowButton = document.querySelector('#runSafeFlow');
const clearLogButton = document.querySelector('#clearLog');
const repoPathInput = document.querySelector('#repoPath');
const configDirectoryInput = document.querySelector('#configDirectory');
const vcVarsPathInput = document.querySelector('#vcVarsPath');

const statusCards = {
  wxc: document.querySelector('#statusWxc'),
  vcvars: document.querySelector('#statusVcvars'),
  admin: document.querySelector('#statusAdmin'),
  profiles: document.querySelector('#statusProfiles')
};

const requiredElements = [
  demoGrid,
  logOutput,
  refreshStatusButton,
  runSafeFlowButton,
  clearLogButton,
  repoPathInput,
  configDirectoryInput,
  vcVarsPathInput,
  statusCards.wxc,
  statusCards.vcvars,
  statusCards.admin,
  statusCards.profiles
];

const safeFlow = [
  'preflight',
  'baseline-network',
  'network-open',
  'filesystem-setup',
  'filesystem-readwrite',
  'filesystem-readonly'
];

let demos = [];
let running = false;

function assertDomReady() {
  if (requiredElements.some(element => element == null)) {
    throw new Error('The page markup does not match public/app.js. Refresh after rebuilding the static files.');
  }
}

function options() {
  return {
    repoPath: repoPathInput.value.trim(),
    configDirectory: configDirectoryInput.value.trim(),
    vcVarsPath: vcVarsPathInput.value.trim()
  };
}

function appendLog(line, className = 'log-stdout') {
  const span = document.createElement('span');
  span.className = className;
  span.textContent = line + '\n';
  logOutput.appendChild(span);
  logOutput.scrollTop = logOutput.scrollHeight;
}

function setRunning(value) {
  running = value;
  document.querySelectorAll('[data-run-demo]').forEach(button => {
    button.disabled = value;
  });
  refreshStatusButton.disabled = value;
  runSafeFlowButton.disabled = value;
}

function setCardStatus(demoId, state) {
  const card = document.querySelector(`[data-demo-card="${demoId}"]`);
  if (!card) {
    return;
  }
  card.classList.remove('running', 'ok', 'failed');
  if (state) {
    card.classList.add(state);
  }
  const status = card.querySelector('[data-demo-status]');
  status.textContent = state || 'ready';
}

function setStatusCard(card, state, text) {
  card.classList.remove('status-ok', 'status-warn', 'status-error');
  if (state) {
    card.classList.add(state);
  }
  card.querySelector('strong').textContent = text;
}

async function loadDemos() {
  const response = await fetch('/api/demos');
  const data = await response.json();
  demos = data.demos;
  renderDemos();
}

function renderDemos() {
  demoGrid.replaceChildren(...demos.map(demo => {
    const card = document.createElement('article');
    card.className = 'demo-card';
    card.dataset.demoCard = demo.id;

    const riskPill = demo.risk === 'admin'
      ? '<span class="pill pill-admin">administrator recommended</span>'
      : '<span class="pill">safe</span>';

    card.innerHTML = `
      <div class="demo-meta">
        <span class="pill">${demo.kind}</span>
        ${riskPill}
        <span class="pill" data-demo-status>ready</span>
      </div>
      <div>
        <h3>${demo.title}</h3>
        <p>${demo.subtitle}</p>
      </div>
      <p>${demo.summary}</p>
      <div class="demo-actions">
        <button class="button button-secondary" type="button" data-run-demo="${demo.id}">Run step</button>
      </div>
    `;

    card.querySelector('[data-run-demo]').addEventListener('click', () => runDemo(demo.id));
    return card;
  }));
}

async function postStream(url, body, onEvent) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body)
  });

  if (!response.ok || !response.body) {
    throw new Error(`Request failed: ${response.status}`);
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { value, done } = await reader.read();
    if (done) {
      break;
    }

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';
    for (const line of lines) {
      if (!line.trim()) {
        continue;
      }
      onEvent(JSON.parse(line));
    }
  }

  if (buffer.trim()) {
    onEvent(JSON.parse(buffer));
  }
}

async function refreshStatus() {
  appendLog('[status] checking local MXC environment...', 'log-event');
  setRunning(true);
  const statusLines = [];
  try {
    await postStream('/api/status', options(), event => {
      if (event.type === 'log') {
        statusLines.push(event.line);
      } else if (event.type === 'error') {
        appendLog(`[status] ${event.message}`, 'log-error');
      }
    });

    const status = JSON.parse(statusLines.join('\n'));
    const missingProfiles = status.profiles.filter(profile => !profile.exists).length;

    setStatusCard(statusCards.wxc, status.wxcExec.exists ? 'status-ok' : 'status-error', status.wxcExec.exists ? 'found' : 'missing');
    setStatusCard(statusCards.vcvars, status.vcvars.found ? 'status-ok' : 'status-error', status.vcvars.found ? 'found' : 'missing');
    setStatusCard(statusCards.admin, status.administrator ? 'status-ok' : 'status-warn', status.administrator ? 'yes' : 'no');
    setStatusCard(statusCards.profiles, missingProfiles === 0 ? 'status-ok' : 'status-error', missingProfiles === 0 ? '4 found' : `${missingProfiles} missing`);

    if (!configDirectoryInput.value.trim()) {
      configDirectoryInput.value = status.configDirectory;
    }

    appendLog('[status] completed', 'log-event');
  } catch (error) {
    appendLog(`[status] ${error.message}`, 'log-error');
  } finally {
    setRunning(false);
  }
}

async function runDemo(demoId) {
  setRunning(true);
  setCardStatus(demoId, 'running');
  appendLog(`[${demoId}] start`, 'log-event');
  let ok = false;

  try {
    await postStream(`/api/run/${encodeURIComponent(demoId)}`, options(), event => {
      if (event.type === 'log') {
        appendLog(event.line, event.stream === 'stderr' ? 'log-stderr' : 'log-stdout');
      } else if (event.type === 'error') {
        appendLog(event.message, 'log-error');
      } else if (event.type === 'end') {
        ok = event.ok;
        appendLog(`[${demoId}] exit ${event.code}`, event.ok ? 'log-event' : 'log-error');
      }
    });
  } catch (error) {
    appendLog(`[${demoId}] ${error.message}`, 'log-error');
  } finally {
    setCardStatus(demoId, ok ? 'ok' : 'failed');
    setRunning(false);
  }

  return ok;
}

async function runSafeFlow() {
  for (const demoId of safeFlow) {
    const ok = await runDemo(demoId);
    if (!ok) {
      appendLog(`[flow] stopped after ${demoId}`, 'log-error');
      return;
    }
  }
  appendLog('[flow] safe flow completed', 'log-event');
}

assertDomReady();
refreshStatusButton.addEventListener('click', refreshStatus);
runSafeFlowButton.addEventListener('click', runSafeFlow);
clearLogButton.addEventListener('click', () => {
  logOutput.replaceChildren();
});

loadDemos()
  .then(refreshStatus)
  .catch(error => appendLog(error.message, 'log-error'));
