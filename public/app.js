const demoGrid = document.querySelector('#demoGrid');
const logOutput = document.querySelector('#logOutput');
const refreshStatusButton = document.querySelector('#refreshStatus');
const runSafeFlowButton = document.querySelector('#runSafeFlow');
const clearLogButton = document.querySelector('#clearLog');
const repoPathInput = document.querySelector('#repoPath');
const configDirectoryInput = document.querySelector('#configDirectory');
const vcVarsPathInput = document.querySelector('#vcVarsPath');
const policyBoard = document.querySelector('#policyBoard');
const stageMap = document.querySelector('#stageMap');
const boardTitle = document.querySelector('#board-title');
const boardSubtitle = document.querySelector('#boardSubtitle');
const resultOrb = document.querySelector('#resultOrb');
const resultLabel = document.querySelector('#resultLabel');
const policyName = document.querySelector('#policyName');
const targetName = document.querySelector('#targetName');
const targetDetail = document.querySelector('#targetDetail');
const fileAccessList = document.querySelector('#fileAccessList');
const accessMeter = document.querySelector('#accessMeter');
const accessLabel = document.querySelector('#accessLabel');
const signalFeed = document.querySelector('#signalFeed');
const exitCode = document.querySelector('#exitCode');
const hostZone = document.querySelector('.host-zone');
const mxcZone = document.querySelector('.mxc-zone');
const targetZone = document.querySelector('.target-zone');
const policyGate = document.querySelector('#policyGate');

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
  policyBoard,
  stageMap,
  boardTitle,
  boardSubtitle,
  resultOrb,
  resultLabel,
  policyName,
  targetName,
  targetDetail,
  fileAccessList,
  accessMeter,
  accessLabel,
  signalFeed,
  exitCode,
  hostZone,
  mxcZone,
  targetZone,
  policyGate,
  statusCards.wxc,
  statusCards.vcvars,
  statusCards.admin,
  statusCards.profiles
];

const scenarioView = {
  preflight: {
    title: 'Preflight launch path',
    subtitle: 'MXC executable and Visual Studio environment readiness check.',
    policy: 'toolchain validation',
    target: 'wxc-exec.exe',
    detail: 'launch probe',
    access: 'inspect',
    posture: 'status',
    resource: 'process'
  },
  'baseline-network': {
    title: 'Baseline network reachability',
    subtitle: 'Normal PowerShell connects outside the MXC boundary.',
    policy: 'outside MXC',
    target: 'www.msftconnecttest.com:80',
    detail: 'host TCP connect',
    access: 'open',
    posture: 'allow',
    resource: 'network'
  },
  'network-open': {
    title: 'Network allowed by profile',
    subtitle: 'internetClient capability permits outbound HTTP inside MXC.',
    policy: 'internetClient',
    target: 'Network :80',
    detail: 'curl inside MXC',
    access: 'open',
    posture: 'allow',
    resource: 'network'
  },
  'network-block': {
    title: 'Network blocked by profile',
    subtitle: 'defaultPolicy=block turns the outbound attempt into a denied path.',
    policy: 'defaultPolicy=block',
    target: 'Network :80',
    detail: 'firewall enforcement',
    access: 'blocked',
    posture: 'deny',
    resource: 'network'
  },
  'filesystem-setup': {
    title: 'Filesystem surface prepared',
    subtitle: 'Demo folders are reset before file access policies are exercised.',
    policy: 'host setup',
    target: 'C:\\mxc-demo-fs',
    detail: 'folder reset',
    access: 'prepare',
    posture: 'status',
    resource: 'file',
    fileAccess: [
      { operation: 'Prepare', file: 'C:\\mxc-demo-fs', state: 'neutral' }
    ]
  },
  'filesystem-readwrite': {
    title: 'Filesystem write allowed',
    subtitle: 'readwritePaths permits output creation under the allowed folder.',
    policy: 'readwritePaths',
    target: 'allowed folder',
    detail: 'read + write',
    access: 'open',
    posture: 'allow',
    resource: 'file',
    fileAccess: [
      { operation: 'Read', file: 'allowed\\input.txt', state: 'ok' },
      { operation: 'Write', file: 'allowed\\output-from-mxc.txt', state: 'ok' }
    ]
  },
  'filesystem-readonly': {
    title: 'Filesystem write denied',
    subtitle: 'readonlyPaths allows reads while denying writes to the protected folder.',
    policy: 'readonlyPaths',
    target: 'readonly folder',
    detail: 'read allowed / write denied',
    access: 'blocked',
    posture: 'deny',
    resource: 'file',
    fileAccess: [
      { operation: 'Read', file: 'readonly\\input.txt', state: 'ok' },
      { operation: 'Write', file: 'readonly\\blocked-write.txt', state: 'blocked' }
    ]
  }
};

const safeFlow = [
  'preflight',
  'baseline-network',
  'network-open',
  'filesystem-setup',
  'filesystem-readwrite',
  'filesystem-readonly'
];

const executionPhases = ['host', 'boundary', 'mxc', 'target'];

let demos = [];
let running = false;
let currentPhaseIndex = 0;

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

function pushSignal(line, className = 'log-stdout') {
  const item = document.createElement('span');
  item.className = className.replace('log-', 'signal-');
  item.textContent = line.length > 92 ? `${line.slice(0, 89)}...` : line;
  signalFeed.prepend(item);
  while (signalFeed.children.length > 5) {
    signalFeed.lastElementChild.remove();
  }
}

function appendLog(line, className = 'log-stdout') {
  const span = document.createElement('span');
  span.className = className;
  span.textContent = line + '\n';
  logOutput.appendChild(span);
  logOutput.scrollTop = logOutput.scrollHeight;
  pushSignal(line, className);
}

function setRunning(value) {
  running = value;
  document.querySelectorAll('[data-run-demo]').forEach(button => {
    button.disabled = value;
  });
  refreshStatusButton.disabled = value;
  runSafeFlowButton.disabled = value;
  document.body.classList.toggle('is-running', value);
}

function revealVisualization() {
  requestAnimationFrame(() => {
    policyBoard.scrollIntoView({ behavior: 'smooth', block: 'start', inline: 'nearest' });
  });
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
  card.classList.remove('status-ok', 'status-warn', 'status-error', 'status-checking');
  if (state) {
    card.classList.add(state);
  }
  card.querySelector('strong').textContent = text;
}

function setBoardMode(mode, state = 'ready', phase = 'idle') {
  policyBoard.dataset.mode = mode;
  policyBoard.dataset.state = state;
  policyBoard.dataset.phase = phase;
  stageMap.dataset.mode = mode;
  stageMap.dataset.state = state;
  stageMap.dataset.phase = phase;
  resultOrb.dataset.mode = mode;
  accessMeter.dataset.mode = mode;
  hostZone.dataset.state = zoneState('host', mode, state, phase);
  mxcZone.dataset.state = zoneState('mxc', mode, state, phase);
  targetZone.dataset.state = zoneState('target', mode, state, phase);
  policyGate.dataset.state = zoneState('boundary', mode, state, phase);
}

function zoneState(zoneName, mode, state, phase) {
  if (mode === 'deny' && state === 'ok' && (zoneName === 'boundary' || zoneName === 'target')) {
    return 'blocked';
  }
  if (state === 'ok' || state === 'failed') {
    return state;
  }
  if (state === 'running') {
    return phase === zoneName ? 'active' : 'waiting';
  }
  return state;
}

function updateBoard(demoId, state = 'ready', phase = 'idle') {
  const view = scenarioView[demoId];
  if (!view) {
    return;
  }

  boardTitle.textContent = view.title;
  boardSubtitle.textContent = view.subtitle;
  policyName.textContent = view.policy;
  targetName.textContent = view.target;
  targetDetail.textContent = view.detail;
  targetZone.dataset.resource = view.resource || 'generic';
  policyGate.dataset.resource = view.resource || 'generic';
  renderFileAccess(view.fileAccess || [], state);
  accessLabel.textContent = view.access;
  setBoardMode(view.posture, state, phase);

  if (state === 'running') {
    resultLabel.textContent = `${phase} running`;
    resultOrb.dataset.state = 'running';
  } else if (state === 'ok') {
    resultLabel.textContent = view.posture === 'deny' ? 'denied as designed' : 'passed';
    resultOrb.dataset.state = 'ok';
  } else if (state === 'failed') {
    resultLabel.textContent = 'attention';
    resultOrb.dataset.state = 'failed';
  } else {
    resultLabel.textContent = view.posture;
    resultOrb.dataset.state = 'ready';
  }
}

function renderFileAccess(items, state) {
  fileAccessList.replaceChildren(...items.map(item => {
    const visualState = state === 'ok' ? item.state : 'neutral';
    const row = document.createElement('div');
    row.className = `file-access-item file-access-${visualState}`;
    row.dataset.reveal = state === 'running' ? 'pending' : 'final';

    const operation = document.createElement('span');
    operation.className = 'file-operation';
    operation.textContent = item.operation;

    const file = document.createElement('strong');
    file.className = 'file-name';
    file.textContent = item.file;

    const result = document.createElement('span');
    result.className = 'file-result';
    result.textContent = resultText(item.state, state);

    row.append(operation, file, result);
    return row;
  }));
}

function resultText(itemState, boardState) {
  if (boardState === 'running') {
    return 'checking';
  }
  if (boardState !== 'ok') {
    return 'pending';
  }
  if (itemState === 'ok') {
    return 'success';
  }
  if (itemState === 'blocked') {
    return 'blocked';
  }
  return 'ready';
}

function advanceExecutionPhase(demoId) {
  const phase = executionPhases[Math.min(currentPhaseIndex, executionPhases.length - 1)];
  currentPhaseIndex += 1;
  updateBoard(demoId, 'running', phase);
}

async function loadDemos() {
  const response = await fetch('/api/demos');
  const data = await response.json();
  demos = data.demos;
  renderDemos();
}

function renderDemos() {
  demoGrid.replaceChildren(...demos.map((demo, index) => {
    const view = scenarioView[demo.id] || {};
    const item = document.createElement('article');
    item.className = 'step-card';
    item.dataset.demoCard = demo.id;

    item.innerHTML = `
      <button class="step-button" type="button" data-run-demo="${demo.id}">
        <span class="step-index">${String(index + 1).padStart(2, '0')}</span>
        <span class="step-copy">
          <strong>${demo.title}</strong>
          <span>${view.detail || demo.subtitle}</span>
        </span>
        <span class="step-state" data-demo-status>ready</span>
      </button>
    `;

    item.querySelector('[data-run-demo]').addEventListener('click', () => runDemo(demo.id));
    item.addEventListener('mouseenter', () => {
      if (!running) {
        updateBoard(demo.id);
      }
    });
    return item;
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
  currentPhaseIndex = 0;
  updateBoard('preflight', 'running', 'host');
  revealVisualization();
  Object.values(statusCards).forEach(card => setStatusCard(card, 'status-checking', 'checking'));
  const statusLines = [];
  try {
    await postStream('/api/status', options(), event => {
      if (event.type === 'log') {
        statusLines.push(event.line);
        advanceExecutionPhase('preflight');
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

    const statusOk = status.wxcExec.exists && status.vcvars.found && missingProfiles === 0;
    updateBoard('preflight', statusOk ? 'ok' : 'failed', 'target');
    appendLog('[status] completed', 'log-event');
  } catch (error) {
    updateBoard('preflight', 'failed', 'target');
    appendLog(`[status] ${error.message}`, 'log-error');
  } finally {
    setRunning(false);
  }
}

async function runDemo(demoId) {
  setRunning(true);
  currentPhaseIndex = 0;
  setCardStatus(demoId, 'running');
  updateBoard(demoId, 'running', 'host');
  revealVisualization();
  appendLog(`[${demoId}] start`, 'log-event');
  exitCode.textContent = '-';
  let ok = false;

  try {
    await postStream(`/api/run/${encodeURIComponent(demoId)}`, options(), event => {
      if (event.type === 'log') {
        advanceExecutionPhase(demoId);
        appendLog(event.line, event.stream === 'stderr' ? 'log-stderr' : 'log-stdout');
      } else if (event.type === 'error') {
        updateBoard(demoId, 'running', 'boundary');
        appendLog(event.message, 'log-error');
      } else if (event.type === 'end') {
        ok = event.ok;
        exitCode.textContent = String(event.code);
        appendLog(`[${demoId}] exit ${event.code}`, event.ok ? 'log-event' : 'log-error');
      }
    });
  } catch (error) {
    appendLog(`[${demoId}] ${error.message}`, 'log-error');
  } finally {
    setCardStatus(demoId, ok ? 'ok' : 'failed');
    updateBoard(demoId, ok ? 'ok' : 'failed', 'target');
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
clearLogButton.addEventListener('click', event => {
  event.preventDefault();
  logOutput.replaceChildren();
  signalFeed.replaceChildren();
});

loadDemos()
  .then(() => {
    updateBoard('preflight');
    return refreshStatus();
  })
  .catch(error => appendLog(error.message, 'log-error'));
