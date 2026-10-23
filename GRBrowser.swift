import Cocoa
import WebKit
import UniformTypeIdentifiers
import CoreWLAN
import CoreLocation
import Security
import Darwin

// MARK: - Camera config
let CAMERA_BASE = "http://192.168.0.1"

// MARK: - HTML UI (embedded)
let APP_HTML: String = ###"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>GR IIIx</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;600&family=DM+Sans:wght@300;400;500;600&display=swap');

  :root {
    --bg: #0a0a0a;
    --surface: #141414;
    --surface2: #1c1c1c;
    --border: #2a2a2a;
    --text: #e8e8e8;
    --text-dim: #666;
    --accent: #ff6b35;
    --green: #4ecdc4;
    --red: #ff4757;
    --mono: 'JetBrains Mono', monospace;
    --sans: 'DM Sans', sans-serif;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: var(--bg); color: var(--text); font-family: var(--sans);
    min-height: 100vh; -webkit-user-select: none; user-select: none;
  }

  header {
    border-bottom: 1px solid var(--border);
    padding: 12px 16px;
    display: flex; align-items: center; justify-content: space-between; gap: 10px;
    position: sticky; top: 0; background: var(--bg); z-index: 100;
    -webkit-app-region: drag;
  }
  header button, header input, header select { -webkit-app-region: no-drag; }

  .logo {
    font-family: var(--mono); font-weight: 600; font-size: 13px;
    letter-spacing: 0.06em; display: flex; align-items: center; gap: 8px; flex-shrink: 0; white-space: nowrap;
  }
  .logo-dot {
    width: 8px; height: 8px; border-radius: 50%;
    background: var(--red); transition: background 0.3s;
  }
  .logo-dot.connected { background: var(--green); }

  .controls { display: flex; flex: 1; gap: 6px; align-items: center; justify-content: flex-end; min-width: 0; }
  header .controls > button { flex-shrink: 0; padding-inline: 8px; }
  .connection-picker { position: relative; flex: 1 1 260px; min-width: 0; max-width: 320px; }
  #networkSelect { display: block; width: 100%; max-width: none; min-width: 0;
    padding: 6px 22px 6px 27px; appearance: none; -webkit-appearance: none; text-overflow: ellipsis; }
  .connection-picker svg { position: absolute; left: 8px; top: 50%; transform: translateY(-50%);
    width: 14px; height: 14px; fill: none; stroke: currentColor; stroke-width: 1.8;
    stroke-linecap: round; stroke-linejoin: round; pointer-events: none; color: var(--green); }
  .connection-picker::after { content: ''; position: absolute; right: 9px; top: 43%; width: 5px; height: 5px;
    border-right: 1px solid var(--text-dim); border-bottom: 1px solid var(--text-dim); transform: rotate(45deg); pointer-events: none; }
  .connection-picker[data-mode="wifi"] .bluetooth-icon,
  .connection-picker[data-mode="bluetooth"] .wifi-icon { display: none; }
  #status { overflow-wrap: anywhere; }
  .status-bar { gap: 8px; flex-wrap: wrap; }

  button {
    font-family: var(--mono); font-size: 10px; font-weight: 500;
    letter-spacing: 0.05em; padding: 6px 12px; border-radius: 5px;
    border: 1px solid var(--border); background: var(--surface);
    color: var(--text); cursor: pointer; transition: all 0.15s; white-space: nowrap;
  }
  button:hover { background: var(--surface2); border-color: var(--accent); }
  button.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  button.primary:hover { opacity: 0.85; }
  button:disabled { opacity: 0.3; cursor: not-allowed; }

  .status-bar {
    font-family: var(--mono); font-size: 10px; color: var(--text-dim);
    padding: 6px 20px; border-bottom: 1px solid var(--border);
    display: flex; justify-content: space-between; align-items: center;
  }
  .view-toggle {
    display: flex; gap: 2px; background: var(--surface); border-radius: 5px; padding: 2px;
  }
  .view-toggle button { border: none; padding: 3px 8px; font-size: 10px; border-radius: 3px; background: transparent; }
  .view-toggle button.active { background: var(--surface2); color: var(--accent); }

  #app { padding: 12px 20px; }

  .empty-state {
    display: flex; flex-direction: column; align-items: center;
    justify-content: center; min-height: 50vh; color: var(--text-dim);
    text-align: center; gap: 10px;
  }
  .empty-state .icon { font-size: 40px; opacity: 0.3; margin-bottom: 6px; }
  .empty-state p { font-family: var(--mono); font-size: 11px; max-width: 300px; line-height: 1.7; }

  .grid {
    display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 3px;
  }
  .grid.list { grid-template-columns: 1fr; gap: 0; }

  .photo-card {
    position: relative; aspect-ratio: 3/2; background: var(--surface);
    border-radius: 3px; overflow: hidden; cursor: pointer; transition: transform 0.12s;
  }
  .photo-card:hover { transform: scale(1.008); }
  .photo-card img { width: 100%; height: 100%; object-fit: cover; display: block; }

  .photo-card .overlay {
    position: absolute; bottom: 0; left: 0; right: 0;
    padding: 6px 8px; background: linear-gradient(transparent, rgba(0,0,0,0.8));
    font-family: var(--mono); font-size: 9px; color: rgba(255,255,255,0.7);
    opacity: 0; transition: opacity 0.12s; display: flex;
    justify-content: space-between; align-items: flex-end;
  }
  .photo-card:hover .overlay { opacity: 1; }

  .photo-card .chk {
    position: absolute; top: 6px; left: 6px; width: 18px; height: 18px;
    border-radius: 50%; border: 2px solid rgba(255,255,255,0.4);
    background: rgba(0,0,0,0.3); display: flex; align-items: center;
    justify-content: center; opacity: 0; transition: opacity 0.12s;
    font-size: 10px; color: #fff;
  }
  .photo-card:hover .chk, .photo-card.sel .chk { opacity: 1; }
  .photo-card.sel .chk { background: var(--accent); border-color: var(--accent); }

  .grid.list .photo-card {
    aspect-ratio: unset; display: flex; align-items: center;
    border-radius: 0; gap: 10px; padding: 6px 10px; border-bottom: 1px solid var(--border);
  }
  .grid.list .photo-card img { width: 44px; height: 30px; border-radius: 2px; flex-shrink: 0; }
  .grid.list .photo-card .overlay { position: static; background: none; opacity: 1; padding: 0; flex: 1; }
  .grid.list .photo-card .chk { position: static; opacity: 1; flex-shrink: 0; }

  .lightbox {
    position: fixed; inset: 0; background: rgba(0,0,0,0.95);
    z-index: 200; display: none; flex-direction: column;
    align-items: center; justify-content: center;
  }
  .lightbox.open { display: flex; }
  .lightbox img { max-width: 92vw; max-height: 82vh; object-fit: contain; border-radius: 3px; }
  .lb-bar { position: absolute; bottom: 20px; display: flex; gap: 6px; align-items: center; }
  .lb-close { position: absolute; top: 14px; right: 14px; }
  .lb-info { position: absolute; top: 14px; left: 14px; font-family: var(--mono); font-size: 11px; color: var(--text-dim); }
  .lb-nav {
    position: absolute; top: 50%; transform: translateY(-50%);
    font-size: 22px; background: rgba(255,255,255,0.05); border: none;
    color: var(--text); width: 44px; height: 44px; border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
  }
  .lb-nav.prev { left: 14px; }
  .lb-nav.next { right: 14px; }

  .toast {
    position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%) translateY(70px);
    font-family: var(--mono); font-size: 11px; background: var(--surface2);
    border: 1px solid var(--border); padding: 8px 18px; border-radius: 7px;
    z-index: 300; transition: transform 0.25s ease; pointer-events: none;
  }
  .toast.show { transform: translateX(-50%) translateY(0); }

  .sel-bar {
    position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
    background: var(--surface2); border: 1px solid var(--border); border-radius: 9px;
    padding: 7px 14px; display: flex; gap: 8px; align-items: center;
    z-index: 150; font-family: var(--mono); font-size: 11px;
    box-shadow: 0 6px 28px rgba(0,0,0,0.5);
  }
  [hidden] { display: none !important; }
  select { color: var(--text); background: var(--surface); border: 1px solid var(--border);
    border-radius: 5px; padding: 6px; font: 11px var(--mono); max-width: 170px; }
  .download-status {
    position: fixed; bottom: 76px; left: 50%; transform: translateX(-50%);
    width: min(440px, calc(100vw - 32px)); box-sizing: border-box;
    padding: 12px 14px; border: 1px solid var(--border); border-radius: 9px;
    background: var(--surface2); box-shadow: 0 6px 28px rgba(0,0,0,0.5);
    z-index: 250; font-family: var(--mono); font-size: 11px; pointer-events: none;
  }
  .download-status[hidden] { display: none; }
  .download-heading { display: flex; justify-content: space-between; gap: 12px; }
  #downloadCounts { color: var(--text-dim); white-space: nowrap; }
  #downloadFilename { margin: 7px 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  #downloadProgress { display: block; width: 100%; height: 6px; accent-color: var(--accent); }
  #downloadPercent { margin-top: 6px; color: var(--accent); min-height: 12px; }
</style>
</head>
<body>

<header>
  <div class="logo"><span class="logo-dot" id="dot"></span> GR IIIx</div>
  <div class="controls">
    <div class="connection-picker" id="connectionPicker" data-mode="wifi">
      <svg class="bluetooth-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m7 7 10 10-5 5V2l5 5L7 17"/></svg>
      <svg class="wifi-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M2 8.8a15 15 0 0 1 20 0M5 12a10 10 0 0 1 14 0M8.5 15.5a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/></svg>
      <select id="networkSelect" aria-label="Wi-Fi connection target" onpointerdown="appMessage('settings')" onchange="targetChanged()">
        <option value="">Current Wi-Fi — checking…</option>
      </select>
    </div>
    <button id="findCameras" onclick="appMessage('findBluetooth')" title="Find nearby Bluetooth cameras">Find cameras…</button>
    <button class="primary" id="connBtn" onclick="doConnect()">CONNECT</button>
    <button id="settingsButton" onclick="openSettings()" aria-label="Settings" title="Settings (⌘,)">⚙</button>
  </div>
</header>

<div class="status-bar">
  <span id="status" role="status" aria-live="polite">Not connected</span>
  <button id="manualWiFi" hidden onclick="useManualWiFi()">Use camera Wi-Fi</button>
  <div style="display:flex;gap:6px;align-items:center">
    <div class="view-toggle">
      <button class="active" onclick="setView('grid',this)">▦</button>
      <button onclick="setView('list',this)">☰</button>
    </div>
    <button onclick="selAll()" id="selAllBtn" disabled>Select all</button>
    <button onclick="dlSelected()" id="dlBtn" data-download="selection" disabled>Download</button>
  </div>
</div>

<div id="app">
  <div class="empty-state" id="empty">
    <div class="icon">◎</div>
    <p>Connect to your GR IIIx Wi-Fi, then hit CONNECT.</p>
  </div>
  <div class="grid" id="grid" style="display:none"></div>
</div>

<div class="lightbox" id="lb">
  <button class="lb-close" onclick="closeLb()">✕</button>
  <div class="lb-info" id="lbInfo"></div>
  <button class="lb-nav prev" onclick="navLb(-1)">‹</button>
  <button class="lb-nav next" onclick="navLb(1)">›</button>
  <img id="lbImg" src="">
  <div class="lb-bar">
    <button onclick="dlCurrent()" data-download="current">↓ FULL RES</button>
    <button onclick="closeLb()">CLOSE</button>
  </div>
</div>

<div class="sel-bar" id="selBar" style="display:none">
  <span id="selCnt">0</span>
  <button onclick="dlSelected()" class="primary" data-download="selection">↓ Download</button>
  <button onclick="clearSel()">Clear</button>
</div>

<div class="download-status" id="downloadStatus" hidden>
  <div class="download-heading">
    <span id="downloadStage" role="status" aria-live="polite" aria-atomic="true"></span>
    <span id="downloadCounts"></span>
  </div>
  <div id="downloadFilename"></div>
  <progress id="downloadProgress" max="1" aria-label="Photo transfer progress"
            aria-describedby="downloadStage downloadCounts downloadFilename"></progress>
  <div id="downloadPercent"></div>
</div>

<div class="toast" id="toast"></div>

<script>
const API = 'gr-cam://camera';
let photos = [], sel = new Set(), lbIdx = 0;
let downloadId = null, downloadSequence = 0, connectionId = null, connectedId = null;
let appSettings = {folder:'', format:'zip', networks:[], available:[], current:'', notice:''};

function toast(m) {
  const t = document.getElementById('toast');
  t.textContent = m; t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 2500);
}

function setView(m, b) {
  document.getElementById('grid').className = m === 'list' ? 'grid list' : 'grid';
  document.querySelectorAll('.view-toggle button').forEach(x => x.classList.remove('active'));
  b.classList.add('active');
}

function appMessage(action, value = {}) {
  try { window.webkit.messageHandlers.app.postMessage({ action, ...value }); }
  catch (error) { _appError(error.message); }
}

let settingsFocus = null;
function openSettings() {
  settingsFocus = document.activeElement;
  appMessage('openSettings');
}
function _settingsClosed() { settingsFocus?.focus(); }
function _appError(message) { toast(message); }
let targetInitialized = false, connectionDraining = false, connectionFinishing = false;
function updateConnectionMode() {
  const select = document.getElementById('networkSelect');
  const bluetooth = select.value.startsWith('bt:');
  document.getElementById('connectionPicker').dataset.mode = bluetooth ? 'bluetooth' : 'wifi';
  const mode = bluetooth ? 'Bluetooth' : 'Wi-Fi';
  select.setAttribute('aria-label', `${mode} connection target`);
  select.title = `${mode} · ${select.selectedOptions[0]?.textContent || ''}`;
}
function targetChanged() {
  const select = document.getElementById('networkSelect');
  updateConnectionMode();
  targetInitialized = true;
  appMessage('selectTarget', {target:select.value});
}
function useManualWiFi() {
  document.getElementById('networkSelect').value = '';
  targetChanged();
  document.getElementById('status').textContent = 'Turn on camera Wi-Fi and join it on your Mac, then press CONNECT.';
}
function _settingsChanged(value) {
  appSettings = value;
  const select = document.getElementById('networkSelect');
  const previous = select.value;
  const known = value.networks.filter(n => value.available.includes(n.id) && n.id !== value.current);
  const currentLabel = value.currentName ? `${value.currentName} (current)` :
    value.wifiConnected === false ? 'No Wi-Fi connection' : 'Current Wi-Fi — name unavailable';
  const cameras = value.bluetoothCameras || [];
  const groups = [['Current Wi-Fi', [['', currentLabel]]],
    ['Bluetooth cameras', cameras.map(c => {
      const name = c.deviceName || c.name;
      const duplicate = cameras.some(other => other.id !== c.id && (other.deviceName || other.name) === name);
      return [c.id, `${name}${duplicate ? ` · ${c.deviceID.slice(-6)}` : ''} · ${c.status}`];
    })],
    ['Camera Wi-Fi networks', known.map(n => [n.id, n.name])]];
  const signature = JSON.stringify(groups);
  if (select.dataset.signature !== signature) {
    select.dataset.signature = signature;
    select.replaceChildren();
    for (const [label, options] of groups) {
      if (!options.length) continue;
      const group = document.createElement('optgroup'); group.label = label;
      for (const [id, name] of options) group.appendChild(new Option(name, id));
      select.appendChild(group);
    }
  }
  const restored = !targetInitialized && value.preferredTarget ? value.preferredTarget : previous;
  select.value = Array.from(select.options).some(o => o.value === restored) ? restored : '';
  if (value.preferredTarget) targetInitialized = true;
  updateConnectionMode();
  document.getElementById('manualWiFi').hidden = !value.manualRecovery;
  document.getElementById('findCameras').disabled = !!value.bluetoothControlsDisabled || downloadId !== null;
  connectionDraining = !!value.connectionDraining;
  connectionFinishing = !!value.connectionFinishing;
  updateDownloadButtons();
}

function doConnect() {
  if (downloadId !== null || connectionDraining) return;
  if (connectionId !== null) { appMessage('cancelConnection'); return; }
  if (connectedId !== null) { appMessage('disconnect'); return; }
  connectionId = `connect-${Date.now()}-${++downloadSequence}`;
  connectedId = null;
  photos = []; sel.clear(); closeLb(); updSel();
  document.getElementById('grid').replaceChildren();
  document.getElementById('empty').style.display = '';
  document.querySelector('#empty p').textContent = 'Connecting to camera…';
  document.getElementById('dot').classList.remove('connected');
  document.getElementById('selAllBtn').disabled = true;
  document.getElementById('status').textContent = 'Preparing connection…';
  appMessage('connect', { id: connectionId, target: document.getElementById('networkSelect').value });
}
function _connectionEvent(event) {
  if (event.phase === 'disconnected' || event.phase === 'remembered') {
    if (event.id !== connectedId || connectionId !== null) return;
    document.getElementById('status').textContent = event.message;
    if (event.phase === 'remembered') return;
    connectedId = null;
    photos = []; sel.clear(); closeLb(); updSel();
    document.getElementById('grid').replaceChildren();
    document.getElementById('grid').style.display = 'none';
    document.getElementById('empty').style.display = '';
    document.querySelector('#empty p').textContent = event.message;
    document.getElementById('dot').classList.remove('connected');
    document.getElementById('selAllBtn').disabled = true;
    updateDownloadButtons();
    return;
  }
  if (connectionId === null || event.id !== connectionId) return;
  document.getElementById('status').textContent = event.warning ? `${event.message} · ${event.warning}` : event.message;
  if (event.phase === 'draining') { connectionDraining = true; connectionFinishing = !!event.finishing; }
  if (['completed', 'failed', 'cancelled'].includes(event.phase)) {
    connectionDraining = false; connectionFinishing = false;
    connectionId = null;
    if (event.phase === 'completed') {
      connectedId = event.id;
      photos = event.photos;
      document.getElementById('dot').classList.add('connected');
      document.getElementById('selAllBtn').disabled = photos.length === 0;
      document.getElementById('empty').style.display = photos.length ? 'none' : '';
      document.querySelector('#empty p').textContent = photos.length ? '' : 'No photos on this camera.';
      render();
    } else { document.querySelector('#empty p').textContent = event.message; }
    toast(event.warning || event.message);
  }
  updateDownloadButtons();
}

function thumb(p) { return `${API}/v1/photos/${p.dir}/${p.file}?size=thumb`; }
function view(p)  { return `${API}/v1/photos/${p.dir}/${p.file}?size=view`; }
function full(p)  { return `${API}/v1/photos/${p.dir}/${p.file}`; }
function key(p)   { return [p.dir,p.file].filter(Boolean).join('/'); }

function render() {
  const g = document.getElementById('grid');
  g.style.display = ''; g.innerHTML = '';
  photos.forEach((p, i) => {
    const c = document.createElement('div');
    c.className = 'photo-card' + (sel.has(key(p)) ? ' sel' : '');
    c.innerHTML = `
      <div class="chk" onclick="event.stopPropagation();togSel(${i})">${sel.has(key(p)) ? '✓' : ''}</div>
      <img src="${thumb(p)}" loading="lazy" onerror="this.style.display='none'">
      <div class="overlay"><span>${p.file}</span><span>${p.dir}</span></div>`;
    c.addEventListener('click', () => openLb(i));
    g.appendChild(c);
  });
}

function togSel(i) {
  const k = key(photos[i]);
  sel.has(k) ? sel.delete(k) : sel.add(k);
  updSel(); render();
}

function selAll() {
  sel.size === photos.length ? sel.clear() : photos.forEach(p => sel.add(key(p)));
  updSel(); render();
}

function clearSel() { sel.clear(); updSel(); render(); }

function updSel() {
  updateDownloadButtons();
  if (sel.size > 0) {
    document.getElementById('selBar').style.display = 'flex';
    document.getElementById('selCnt').textContent = `${sel.size} selected`;
  } else {
    document.getElementById('selBar').style.display = 'none';
  }
  document.getElementById('selAllBtn').textContent = sel.size === photos.length ? 'Deselect all' : 'Select all';
}

function openLb(i) {
  lbIdx = i; const p = photos[i];
  document.getElementById('lbImg').src = view(p);
  document.getElementById('lbInfo').textContent = `${p.file}  ·  ${p.dir}  ·  ${i+1}/${photos.length}`;
  document.getElementById('lb').classList.add('open');
  updateDownloadButtons();
}
function closeLb() { document.getElementById('lb').classList.remove('open'); }
function navLb(d) { lbIdx = (lbIdx + d + photos.length) % photos.length; openLb(lbIdx); }

document.addEventListener('keydown', e => {
  if (e.metaKey && e.key === ',') { e.preventDefault(); openSettings(); return; }
  if (!document.getElementById('lb').classList.contains('open')) return;
  if (e.key === 'Escape') closeLb();
  if (e.key === 'ArrowLeft') navLb(-1);
  if (e.key === 'ArrowRight') navLb(1);
});

function dlCurrent() {
  const p = photos[lbIdx];
  if (p) startDownload([key(p)]);
}

function dlSelected() {
  startDownload(photos.filter(p => sel.has(key(p))).map(key));
}

function updateDownloadButtons() {
  document.getElementById('connBtn').disabled = downloadId !== null || connectionDraining;
  document.getElementById('connBtn').textContent = connectionDraining ? (connectionFinishing ? 'FINISHING…' : 'CANCELLING…') : connectionId !== null ? 'CANCEL' : connectedId !== null ? 'DISCONNECT' : 'CONNECT';
  document.getElementById('networkSelect').disabled = downloadId !== null || connectionId !== null || connectedId !== null;
  document.getElementById('findCameras').disabled = downloadId !== null || connectionId !== null || connectedId !== null;
  document.querySelectorAll('[data-download]').forEach(button => {
    button.disabled = downloadId !== null || connectionId !== null ||
      (button.dataset.download === 'selection' ? sel.size === 0 : !photos[lbIdx]);
  });
}

function startDownload(files) {
  if (downloadId !== null || connectionId !== null || files.length === 0) return;
  downloadId = `${Date.now()}-${++downloadSequence}`;
  updateDownloadButtons();
  _downloadEvent({ id: downloadId, phase: 'preparing', completed: 0,
                   total: files.length, filename: files[0].split('/').pop() });
  try {
    window.webkit.messageHandlers.download.postMessage(JSON.stringify({ id: downloadId, files }));
  } catch (error) {
    _downloadEvent({ id: downloadId, phase: 'failed', message: `Download failed: ${error.message}` });
  }
}

// Native events are JSON objects; filenames and errors never become executable code.
function _downloadEvent(event) {
  if (downloadId === null || event.id !== downloadId) return;
  const progress = document.getElementById('downloadProgress');
  if (['completed', 'failed', 'cancelled'].includes(event.phase)) {
    document.getElementById('downloadStatus').hidden = true;
    progress.removeAttribute('value');
    document.getElementById('downloadPercent').textContent = '';
    downloadId = null;
    updateDownloadButtons();
    toast(event.message);
    return;
  }
  const stages = { preparing: 'Preparing download folder…', downloading: 'Downloading…',
    archiving: 'Creating ZIP…', saving: 'Saving…' };
  document.getElementById('downloadStatus').hidden = false;
  const stage = document.getElementById('downloadStage');
  if (stage.textContent !== stages[event.phase]) stage.textContent = stages[event.phase];
  document.getElementById('downloadCounts').textContent = `${event.completed}/${event.total} files`;
  document.getElementById('downloadFilename').textContent = event.filename || '';
  if (event.phase === 'downloading' && Number.isFinite(event.fraction)) {
    const fraction = Math.max(0, Math.min(1, event.fraction));
    progress.value = fraction;
    document.getElementById('downloadPercent').textContent = `Transfer ${Math.floor(fraction * 100)}%`;
  } else {
    progress.removeAttribute('value');
    document.getElementById('downloadPercent').textContent = '';
  }
}

updateDownloadButtons();
appMessage('ready');
</script>
</body>
</html>
"""###

// The settings form lives in its own native modal window, separate from the browser.
let SETTINGS_HTML: String = ###"""
<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: light dark; font: 13px -apple-system, BlinkMacSystemFont, sans-serif; }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 22px 24px; background: #f3f3f3; color: #222; height: 100vh; display: flex; }
  main { flex: 1; min-width: 0; min-height: 0; display: flex; flex-direction: column; }
  main > :not(.device-section), .device-section > :not(.settings-list) { flex-shrink: 0; }
  .device-section { display: flex; flex-direction: column; flex: 1 1 auto; min-height: 0; }
  .device-controls { display: flex; align-items: center; gap: 12px; }
  .device-controls > p { flex: 1; min-width: 0; margin: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .device-controls > button { flex-shrink: 0; }
  #bluetoothTitle { margin-bottom: 6px; }
  .bluetooth-instructions { margin: 0 0 8px; }
  .bluetooth-instructions small { line-height: 1.4; }
  @media (prefers-color-scheme: dark) { body { background: #252525; color: #eee; } }
  h2 { font-size: 14px; margin: 0 0 12px; }
  section + section { border-top: 1px solid #8885; margin-top: 20px; padding-top: 18px; }
  label { display: block; margin: 16px 0 6px; }
  button, select { font: inherit; min-height: 26px; }
  button { padding: 3px 12px; }
  #folderPath { display: block; font-size: 12px; overflow-wrap: anywhere; margin-bottom: 8px; }
  .settings-list { list-style: none; margin: 10px 0 0; padding: 0; height: 134px; min-height: 46px;
    overflow-y: auto; border: 1px solid #8885; border-radius: 6px; }
  .known-network { display: flex; gap: 12px; align-items: center; justify-content: space-between;
    height: 44px; padding: 4px 10px; }
  .known-network + .known-network { border-top: 1px solid #8884; }
  .network-description { min-width: 0; }
  .network-description > * { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .empty-list { padding: 12px 10px; opacity: 0.7; }
  .remove-device { display: flex; align-items: center; justify-content: center; flex: 0 0 28px;
    width: 28px; height: 28px; padding: 4px; border: 0; border-radius: 4px; background: transparent; color: inherit; }
  .remove-device:hover:enabled { background: #8883; }
  .remove-device:disabled { opacity: 0.35; }
  .remove-device svg { width: 16px; height: 16px; }
  small, #networkNotice { opacity: 0.7; font-size: 11px; line-height: 1.5; }
  #settingsError { color: #d33; font-size: 12px; }
</style></head><body>
<main aria-label="Settings">
  <section aria-labelledby="downloadsTitle">
    <h2 id="downloadsTitle">Downloads</h2>
    <label>Save folder</label><span id="folderPath">Choose a download folder</span>
    <button id="chooseFolder" onclick="appMessage('folder')">Choose folder…</button>
    <label for="exportFormat">Default batch format</label>
    <select id="exportFormat" onchange="appMessage('format', {value:this.value})">
      <option value="zip">ZIP archive</option><option value="separate">Separate files</option>
    </select>
  </section>
  <section class="device-section" aria-labelledby="bluetoothTitle">
    <h2 id="bluetoothTitle">Bluetooth cameras</h2>
    <p class="bluetooth-instructions"><small>Enable Bluetooth on the camera, choose Pairing, and complete the macOS passkey prompt when connecting. Set Action Mode to On anytime to connect while the camera is off.</small></p>
    <div class="device-controls">
      <p id="bluetoothNotice" role="status"></p>
      <button id="findBluetoothButton" onclick="appMessage('findBluetooth')">Enable Bluetooth / Find cameras…</button>
    </div>
    <ul id="knownBluetooth" class="settings-list" aria-labelledby="bluetoothTitle" tabindex="0"><li class="empty-list">No Bluetooth cameras remembered yet.</li></ul>
  </section>
  <section class="device-section" aria-labelledby="networksTitle">
    <h2 id="networksTitle">Known camera networks</h2>
    <div class="device-controls">
      <p id="networkNotice"></p>
      <button id="discoverButton" onclick="appMessage('discover')">Enable Wi-Fi discovery…</button>
    </div>
    <ul id="knownNetworks" class="settings-list" aria-labelledby="networksTitle" tabindex="0"><li class="empty-list">No camera networks remembered yet.</li></ul>
  </section>
  <p id="settingsError" role="alert"></p>
</main>
<script>
function appMessage(action, value = {}) { window.webkit.messageHandlers.app.postMessage({action, ...value}); }
function _appError(message) { document.getElementById('settingsError').textContent = message; }
function settingsContentHeight() {
  // Measure three rows per list; flex layout shortens the lists on smaller screens.
  document.body.style.height = 'auto';
  const height = Math.ceil(document.body.getBoundingClientRect().height);
  document.body.style.height = '100vh';
  return height;
}
function removeDeviceButton(label) {
  const button = document.createElement('button'); button.type = 'button'; button.className = 'remove-device';
  button.setAttribute('aria-label', label); button.title = label;
  button.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/></svg>';
  return button;
}
function emptyList(list, message) {
  const row = document.createElement('li'); row.className = 'empty-list'; row.textContent = message;
  list.appendChild(row);
}
function renderBluetoothList(cameras) {
  const bluetoothList = document.getElementById('knownBluetooth');
  const records = JSON.stringify(cameras);
  if (bluetoothList.dataset.records === records) return;
  bluetoothList.dataset.records = records;
  bluetoothList.replaceChildren();
  for (const camera of cameras) {
    const row = document.createElement('li'); row.className = 'known-network';
    const label = document.createElement('div'); label.className = 'network-description';
    const name = document.createElement('div'); name.textContent = camera.name;
    const detail = document.createElement('small'); detail.textContent = `${camera.deviceName} · ${camera.status}`;
    label.append(name, detail); label.title = `${camera.name} (${camera.deviceName}) · ${camera.status}`;
    row.appendChild(label);
    if (camera.remembered) {
      const button = removeDeviceButton(`Forget camera ${camera.name}`);
      button.disabled = camera.active;
      if (camera.active) button.title = 'Disconnect and finish active operations before forgetting this camera.';
      button.onclick = () => appMessage('forgetBluetooth', {id:camera.deviceID}); row.appendChild(button);
    }
    bluetoothList.appendChild(row);
  }
  if (!cameras.length) emptyList(bluetoothList, 'No Bluetooth cameras remembered yet.');
}
function _settingsChanged(value) {
  document.getElementById('bluetoothNotice').textContent = value.bluetoothState || 'Bluetooth access is requested only when you choose Find cameras.';
  document.getElementById('bluetoothNotice').title = document.getElementById('bluetoothNotice').textContent;
  document.getElementById('findBluetoothButton').disabled = !!value.bluetoothControlsDisabled;
  renderBluetoothList(value.bluetoothCameras || []);
  document.getElementById('folderPath').textContent = value.folder || 'Choose a download folder';
  document.getElementById('exportFormat').value = value.format;
  document.getElementById('networkNotice').textContent = value.notice || 'Remembered after a successful camera connection.';
  document.getElementById('networkNotice').title = document.getElementById('networkNotice').textContent;
  document.getElementById('discoverButton').textContent = value.discoveryAllowed ? 'Refresh Wi-Fi discovery' : 'Enable Wi-Fi discovery…';
  const list = document.getElementById('knownNetworks');
  const records = JSON.stringify(value.networks);
  if (list.dataset.records === records) return;
  list.dataset.records = records;
  list.replaceChildren();
  for (const network of value.networks) {
    const row = document.createElement('li'); row.className = 'known-network';
    const description = document.createElement('div'); description.className = 'network-description';
    const name = document.createElement('div'); name.textContent = network.name;
    const last = document.createElement('small');
    last.textContent = `Last connected: ${new Date(network.lastConnected * 1000).toLocaleString()}`;
    description.append(name, last);
    description.title = `${network.name} · ${last.textContent}`;
    const forget = removeDeviceButton(`Forget ${network.name}`);
    forget.disabled = network.forgetting;
    if (network.forgetting) { forget.title = 'Forgetting…'; forget.setAttribute('aria-busy', 'true'); }
    forget.onclick = () => appMessage('forget', {id:network.id});
    row.append(description, forget); list.appendChild(row);
  }
  if (!value.networks.length) emptyList(list, 'No camera networks remembered yet.');
}
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' || (event.metaKey && event.key.toLowerCase() === 'w')) {
    event.preventDefault(); appMessage('closeSettings');
  }
});
document.getElementById('chooseFolder').focus();
appMessage('settingsReady');
</script></body></html>
"""###

// MARK: - Custom URL Scheme Handler
// Intercepts "gr-cam://" requests and forwards to the camera over HTTP

class CameraSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        // Build camera URL: gr-cam://camera/v1/photos -> http://192.168.0.1/v1/photos
        var cameraURLString = CAMERA_BASE + (components.path)
        if let query = components.query {
            cameraURLString += "?\(query)"
        }

        guard let cameraURL = URL(string: cameraURLString) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        var request = URLRequest(url: cameraURL, timeoutInterval: 30)
        request.setValue("GRBrowser/1.0", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                urlSchemeTask.didFailWithError(error)
                return
            }
            guard let data = data, let response = response as? HTTPURLResponse else {
                urlSchemeTask.didFailWithError(URLError(.unknown))
                return
            }

            let mimeType = response.mimeType ?? "application/octet-stream"
            let resp = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": mimeType,
                    "Content-Length": "\(data.count)",
                    "Access-Control-Allow-Origin": "*"
                ]
            )!
            urlSchemeTask.didReceive(resp)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }
        task.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // No-op; tasks are short-lived
    }
}

// MARK: - Native settings and platform services

func appError(_ message: String) -> Error {
    NSError(domain: "GRBrowser", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

struct CameraNetwork: Equatable {
    let id: String
    let name: String
    let secured: Bool
    init(name: String, data: Data? = nil, secured: Bool = true) {
        self.name = name
        self.id = (data ?? Data(name.utf8)).base64EncodedString()
        self.secured = secured
    }
}

struct KnownCameraNetwork {
    let network: CameraNetwork
    let lastConnected: Date
}

enum ExportFormat: String { case zip, separate }

// Read and changed on the main thread; download operations receive immutable snapshots.
final class AppPreferences {
    let defaults: UserDefaults
    private let key = "settings.v1"
    private(set) var format: ExportFormat = .zip
    private(set) var networks: [KnownCameraNetwork] = []
    private var folderBookmark: Data?
    private(set) var revisions: [String: Int] = [:]
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let record = defaults.dictionary(forKey: key), record["version"] as? Int == 1 else { return }
        format = ExportFormat(rawValue: record["format"] as? String ?? "") ?? .zip
        folderBookmark = record["folder"] as? Data
        var seen = Set<String>()
        for entry in record["networks"] as? [[String: Any]] ?? [] {
            guard let id = entry["id"] as? String, let data = Data(base64Encoded: id),
                  !data.isEmpty, data.count <= 32, seen.insert(id).inserted,
                  let name = entry["name"] as? String, !name.isEmpty,
                  let time = entry["lastConnected"] as? Double, time.isFinite else { continue }
            networks.append(KnownCameraNetwork(network: CameraNetwork(name: name, data: data),
                                                lastConnected: Date(timeIntervalSince1970: time)))
        }
        networks.sort { $0.lastConnected > $1.lastConnected }
    }

    func folder() -> URL? {
        guard let bookmark = folderBookmark else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            folderBookmark = refreshed
            persist(notify: false)
        }
        return url
    }

    static func usableFolder(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            && directory.boolValue && FileManager.default.isWritableFile(atPath: url.path)
    }

    func setFolder(_ url: URL) throws {
        guard Self.usableFolder(url) else { throw appError("Choose an available, writable folder.") }
        folderBookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        persist()
    }

    func setFormat(_ value: ExportFormat) { format = value; persist() }

    func remember(_ network: CameraNetwork, at date: Date) {
        networks.removeAll { $0.network.id == network.id }
        networks.insert(KnownCameraNetwork(network: network, lastConnected: date), at: 0)
        persist()
    }

    func invalidateHistory(for id: String) { revisions[id, default: 0] += 1 }
    func forget(_ id: String) { networks.removeAll { $0.network.id == id }; persist() }

    private func persist(notify: Bool = true) {
        var record: [String: Any] = ["version": 1, "format": format.rawValue,
            "networks": networks.map { ["id": $0.network.id, "name": $0.network.name,
                                        "lastConnected": $0.lastConnected.timeIntervalSince1970] }]
        record["folder"] = folderBookmark
        defaults.set(record, forKey: key)
        if notify { onChange?() }
    }
}

func pickDownloadFolder(window: NSWindow?, initial: URL?, completion: @escaping (URL?) -> Void) {
    guard window?.attachedSheet == nil else { completion(nil); return }
    let panel = NSOpenPanel()
    panel.title = "Choose download folder"
    panel.prompt = "Choose"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = initial
    let respond: (NSApplication.ModalResponse) -> Void = { completion($0 == .OK ? panel.url : nil) }
    if let window = window { panel.beginSheetModal(for: window, completionHandler: respond) }
    else { panel.begin(completionHandler: respond) }
}

protocol WiFiAccess {
    func enabled() -> Bool
    func current() -> CameraNetwork?
    func scan() throws -> [CameraNetwork]
    func join(_ network: CameraNetwork, password: String?) throws
    func ready(on network: CameraNetwork?) -> Bool
}

extension WiFiAccess { func enabled() -> Bool { true } }

final class MacWiFi: WiFiAccess {
    func enabled() -> Bool { interface()?.powerOn() == true }
    private var scanned: [String: CWNetwork] = [:]
    private func interface() -> CWInterface? { CWWiFiClient.shared().interface() }
    func current() -> CameraNetwork? {
        guard let interface = interface(), interface.powerOn() else { return nil }
        return Self.network(name: interface.ssid(), data: interface.ssidData(), secured: interface.security() != .none)
    }
    static func network(name: String?, data: Data?, secured: Bool) -> CameraNetwork? {
        // CoreWLAN can expose one representation before the other after association/authorization.
        guard let bytes = data ?? name.map({ Data($0.utf8) }), !bytes.isEmpty,
              let display = name ?? String(data: bytes, encoding: .utf8), !display.isEmpty else { return nil }
        return CameraNetwork(name: display, data: bytes, secured: secured)
    }
    func scan() throws -> [CameraNetwork] {
        guard let interface = interface(), interface.powerOn() else { throw appError("Wi-Fi is off or unavailable.") }
        scanned = [:]
        var found: [CameraNetwork] = []
        for network in try interface.scanForNetworks(withSSID: nil) {
            guard let value = Self.network(name: network.ssid, data: network.ssidData,
                                          secured: !network.supportsSecurity(.none)) else { continue }
            if scanned[value.id] == nil { found.append(value) }
            scanned[value.id] = network
        }
        return found
    }
    func join(_ network: CameraNetwork, password: String?) throws {
        guard let interface = interface(), let target = scanned[network.id] else {
            throw appError("The selected network is no longer nearby.")
        }
        do { try interface.associate(to: target, password: password) }
        catch { throw appError("Could not join the selected Wi-Fi. Check its password and try again.") }
    }
    func ready(on network: CameraNetwork?) -> Bool {
        guard let interface = interface(), interface.powerOn(), let name = interface.interfaceName else { return false }
        if let network = network, current()?.id != network.id { return false }
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return false }
        defer { freeifaddrs(addresses) }
        var address = addresses
        while let item = address {
            defer { address = item.pointee.ifa_next }
            guard String(cString: item.pointee.ifa_name) == name,
                  let socket = item.pointee.ifa_addr, socket.pointee.sa_family == UInt8(AF_INET) else { continue }
            let ip = UnsafeRawPointer(socket).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr.s_addr
            if ip != 0 { return true }
        }
        return false
    }
}

protocol WiFiAuthorization: AnyObject {
    var allowed: Bool { get }
    func request(_ completion: @escaping (Bool) -> Void)
}

final class MacWiFiAuthorization: NSObject, WiFiAuthorization, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var callbacks: [(Bool) -> Void] = []
    override init() { super.init(); manager.delegate = self }
    var allowed: Bool {
        CLLocationManager.locationServicesEnabled() &&
            manager.authorizationStatus == .authorizedAlways
    }
    func request(_ completion: @escaping (Bool) -> Void) {
        guard manager.authorizationStatus == .notDetermined, CLLocationManager.locationServicesEnabled() else {
            completion(allowed); return
        }
        callbacks.append(completion)
        guard callbacks.count == 1 else { return }
        manager.requestWhenInUseAuthorization()
        // An unanswered permission dialog must not indefinitely block manual camera access.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.respond() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined { respond() }
    }
    private func respond() {
        let pending = callbacks; callbacks = []
        pending.forEach { $0(allowed) }
    }
}

protocol CameraCredentials {
    func password(for id: String) throws -> String?
    func save(_ password: String, for id: String) throws
    func remove(_ id: String) throws
}

// Read-only access to macOS-owned Wi-Fi credentials; writes/deletion stay app-owned.
protocol SavedWiFiCredentials {
    func password(for id: String) throws -> String?
}

enum SavedWiFiCredentialError: Error { case cancelled }

final class MacWiFiCredentials: SavedWiFiCredentials {
    typealias Lookup = (CWKeychainDomain, Data) -> (OSStatus, String?)
    private let lookup: Lookup
    init(lookup: @escaping Lookup = MacWiFiCredentials.lookup) { self.lookup = lookup }

    private static func lookup(_ domain: CWKeychainDomain, _ ssid: Data) -> (OSStatus, String?) {
        var password: NSString?
        let status = CWKeychainFindWiFiPassword(domain, ssid, &password)
        return (status, password as String?)
    }

    func password(for id: String) throws -> String? {
        guard let ssid = Data(base64Encoded: id), !ssid.isEmpty, ssid.count <= 32 else {
            throw appError("The selected Wi-Fi identity is invalid.")
        }
        for domain in [CWKeychainDomain.user, .system] {
            let (status, password) = lookup(domain, ssid)
            if status == errSecSuccess, let password = password, !password.isEmpty { return password }
            if status == errSecUserCanceled { throw SavedWiFiCredentialError.cancelled }
            // No saved item: try the other domain. Denied/locked/unavailable access:
            // fall back to app-owned credentials without another macOS access request.
            if status != errSecItemNotFound && status != errSecSuccess { return nil }
        }
        return nil
    }
}

final class KeychainCameraCredentials: CameraCredentials {
    private let service: String
    init(service: String = "local.GRBrowser.camera-wifi") { self.service = service }
    private func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: id]
    }
    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw appError("Camera password Keychain access failed (\(status)).") }
    }
    func password(for id: String) throws -> String? {
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw appError("The stored camera password cannot be read.")
        }
        return value
    }
    func save(_ password: String, for id: String) throws {
        let attributes = [kSecValueData as String: Data(password.utf8)]
        let status = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(id)
            item[kSecValueData as String] = Data(password.utf8)
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    func remove(_ id: String) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}

struct CameraPhoto { let dir: String; let file: String }
protocol CameraVerification {
    func identify(_ identity: BluetoothIdentity, completion: @escaping (Result<Void, Error>) -> Void)
    func verify(_ completion: @escaping (Result<[CameraPhoto], Error>) -> Void)
    func ping(_ completion: @escaping (Result<Void, Error>) -> Void)
    func cancel()
}

extension CameraVerification {
    func identify(_ identity: BluetoothIdentity, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(appError("Camera identity verification is unavailable.")))
    }
    func ping(_ completion: @escaping (Result<Void, Error>) -> Void) {
        verify { completion($0.map { _ in () }) }
    }
}

final class HTTPCameraVerification: CameraVerification {
    private let base: URL
    private let session: URLSession
    private var generation = UUID()
    private var task: URLSessionDataTask?
    init(base: URL = URL(string: CAMERA_BASE)!) {
        self.base = base
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 8
        session = URLSession(configuration: config)
    }
    func cancel() { generation = UUID(); task?.cancel(); task = nil }
    func ping(_ completion: @escaping (Result<Void, Error>) -> Void) {
        cancel()
        request("v1/ping", token: generation) { completion($0.map { _ in () }) }
    }
    func verify(_ completion: @escaping (Result<[CameraPhoto], Error>) -> Void) {
        cancel()
        let token = generation
        request("v1/ping", token: token) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                self.request("v1/photos", token: token) { result in
                    completion(result.flatMap { data in
                        Result {
                            do { return try Self.photos(from: data) }
                            catch { throw appError("Camera returned an invalid photo list.") }
                        }
                    })
                }
            }
        }
    }
    private func request(_ path: String, token: UUID, completion: @escaping (Result<Data, Error>) -> Void) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.setValue("GRBrowser/1.0", forHTTPHeaderField: "User-Agent")
        task = session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                guard error == nil, let response = response as? HTTPURLResponse,
                      (200...299).contains(response.statusCode), let data = data else {
                    completion(.failure(appError(path == "v1/ping" ? "Camera is unavailable." : "Could not load camera photos.")))
                    return
                }
                completion(.success(data))
            }
        }
        task?.resume()
    }
    func identify(_ identity: BluetoothIdentity, completion: @escaping (Result<Void, Error>) -> Void) {
        let token = generation
        request("v1/props", token: token) { result in
            completion(result.flatMap { data in Result {
                guard let props = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      props["model"] as? String == identity.model else {
                    throw appError("Wi-Fi camera identity does not match the selected Bluetooth camera.")
                }
                if let serial = identity.serial, let other = (props["serialNo"] ?? props["serialNumber"] ?? props["serial"]) as? String, serial != other {
                    throw appError("Wi-Fi camera serial does not match the selected Bluetooth camera.")
                }
            } })
        }
    }
    static func photos(from data: Data) throws -> [CameraPhoto] {
        let json = try JSONSerialization.jsonObject(with: data)
        var photos: [CameraPhoto] = []
        func append(_ value: Any, directory: String) throws {
            let filename = value as? String ?? (value as? [String: Any])?["name"] as? String
            guard let filename = filename, !filename.isEmpty else { throw appError("Invalid camera photo list.") }
            photos.append(CameraPhoto(dir: directory, file: filename))
        }
        if let dictionary = json as? [String: Any], let dirs = dictionary["dirs"] as? [[String: Any]] {
            for dir in dirs {
                guard let name = dir["name"] as? String, let files = dir["files"] as? [Any] else {
                    throw appError("Invalid camera photo list.")
                }
                for file in files { try append(file, directory: name) }
            }
        } else if let list = json as? [[String: Any]] {
            for item in list {
                guard let name = item["name"] as? String ?? item["file"] as? String else {
                    throw appError("Invalid camera photo list.")
                }
                try append(name, directory: item["dir"] as? String ?? item["directory"] as? String ?? "")
            }
        } else { throw appError("Invalid camera photo list.") }
        return photos.sorted { $0.file > $1.file }
    }
}

// Main-thread lifecycle; blocking Wi-Fi and Keychain calls run on the serial worker.
final class CameraConnection {
    let bluetooth: CameraBluetoothAccess
    let devices: BluetoothDeviceStore
    var selectedBluetooth: UUID?
    var nextBluetoothDiscovery = Date.distantPast
    var bluetoothLabel = ""
    var releasedBluetooth: UUID?
    var manualRecovery = false
    var selectionRevision = 0
    let preferences: AppPreferences
    let wifi: WiFiAccess
    let authorization: WiFiAuthorization
    let credentials: CameraCredentials
    let savedCredentials: SavedWiFiCredentials
    let camera: CameraVerification
    let health: CameraVerification
    let worker = DispatchQueue(label: "GRBrowser.wifi", qos: .userInitiated)
    let now: () -> Date
    let later: (TimeInterval, @escaping () -> Void) -> Void
    let timeout: TimeInterval
    var attempt: Attempt?
    var session: Session?
    var healthCheck: UUID?
    var scanGeneration = 0
    var scanning = false
    var checkingCurrent = false
    var nextDiscovery = Date.distantPast
    var forgetting = Set<String>()
    private(set) var nearby: [CameraNetwork] = []
    private(set) var currentNetwork: CameraNetwork?
    var wifiReady: Bool?
    var currentID: String? { currentNetwork?.id }
    private(set) var notice = "Enable Wi-Fi discovery to remember and reconnect to camera networks."
    var onChange: (() -> Void)?
    var onEvent: (([String: Any]) -> Void)?
    var canConnect: () -> Bool = { true }
    var passwordPrompt: (String, @escaping ((String, Bool)?) -> Void) -> Void = { _, done in done(nil) }
    var isConnecting: Bool { attempt != nil }
    var isConnected: Bool { session != nil }

    // The app timer also discovers remembered networks that appear after the initial scan.
    // Permission requests remain explicit; polling never prompts or switches Wi-Fi.
    func poll(discover: Bool = true) {
        checkConnection()
        pollBluetooth(discover: discover)
        if discover { refreshCurrentNetwork() }
        if discover, !preferences.networks.isEmpty, authorization.allowed, now() >= nextDiscovery { refresh() }
    }

    // Reading the current interface does not scan or change Wi-Fi and remains safe during downloads.
    func refreshCurrentNetwork() {
        guard !checkingCurrent, !isConnecting else { return }
        checkingCurrent = true
        let generation = scanGeneration
        let allowed = authorization.allowed
        worker.async {
            let network = allowed ? self.wifi.current() : nil
            let ready = self.wifi.ready(on: nil)
            DispatchQueue.main.async {
                self.checkingCurrent = false
                guard self.scanGeneration == generation, !self.isConnecting else { return }
                var changed = self.setCurrent(network, ready: ready)
                if !allowed, !self.nearby.isEmpty { self.nearby = []; changed = true }
                if changed { self.onChange?() }
            }
        }
    }

    @discardableResult func setCurrent(_ network: CameraNetwork?, ready: Bool) -> Bool {
        let changed = currentNetwork != network || wifiReady != ready
        currentNetwork = network; wifiReady = ready
        return changed
    }

    final class Session {
        let id: String
        let revisions: [String: Int]
        let photoCount: Int
        let bluetoothID: UUID?
        var network: CameraNetwork?
        init(job: Attempt, photoCount: Int) {
            id = job.id; revisions = job.revisions; network = job.initial; self.photoCount = photoCount; bluetoothID = job.bluetoothID
        }
    }

    final class Attempt {
        let id: String
        let cancellation = ConnectionCancellation()
        var target: String?
        var bluetoothID: UUID?
        var bluetoothRevision = 0
        var bluetoothIdentity: BluetoothIdentity?
        var bluetoothCredentials: BluetoothWiFiCredentials?
        var credentialRefreshed = false
        var deadline: Date?
        var terminal: String?
        var selectionRevision = 0
        var propsVerified = false
        let revisions: [String: Int]
        var initial: CameraNetwork?
        var pendingPassword: String?
        var triedPasswords = Set<String>()
        var verified = false
        var lastFailure: Error?
        var waitingForNetwork = false
        init(id: String, target: String?, revisions: [String: Int]) {
            self.id = id; self.target = target; self.revisions = revisions
        }
    }

    init(bluetooth: CameraBluetoothAccess = BluetoothCamera(), devices: BluetoothDeviceStore? = nil,
         preferences: AppPreferences, wifi: WiFiAccess = MacWiFi(),
         authorization: WiFiAuthorization = MacWiFiAuthorization(),
         credentials: CameraCredentials = KeychainCameraCredentials(),
         savedCredentials: SavedWiFiCredentials = MacWiFiCredentials(),
         camera: CameraVerification = HTTPCameraVerification(),
         health: CameraVerification = HTTPCameraVerification(), timeout: TimeInterval = 15,
         now: @escaping () -> Date = Date.init,
         later: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
         }) {
        self.bluetooth = bluetooth; self.devices = devices ?? BluetoothDeviceStore(defaults: preferences.defaults)
        self.selectedBluetooth = self.devices.preferred
        self.preferences = preferences; self.wifi = wifi; self.authorization = authorization
        self.credentials = credentials; self.savedCredentials = savedCredentials
        self.camera = camera; self.health = health; self.timeout = timeout
        self.now = now; self.later = later
        bluetooth.onChange = { [weak self] in self?.onChange?() }
    }

    // Poll local Wi-Fi and the camera, including when SSID access is denied. No internet is required.
    func checkConnection() {
        guard let connected = session, !isConnecting, healthCheck == nil else { return }
        let token = UUID()
        healthCheck = token
        let allowed = authorization.allowed
        worker.async {
            let ready = self.wifi.ready(on: nil)
            let network = allowed ? self.wifi.current() : nil
            DispatchQueue.main.async {
                guard self.session === connected, self.healthCheck == token else { return }
                if self.setCurrent(network, ready: ready) { self.onChange?() }
                guard ready, connected.network == nil || network == nil || connected.network?.id == network?.id else {
                    self.disconnected(connected); return
                }
                let needsIdentity = connected.network == nil && network != nil
                let respond: (Result<Void, Error>) -> Void = { result in
                    guard self.session === connected, self.healthCheck == token else { return }
                    guard case .success = result else { self.disconnected(connected); return }
                    // Confirm identity around a fresh full verification before learning a late SSID.
                    self.worker.async {
                        let final = allowed ? self.wifi.current() : nil
                        DispatchQueue.main.async {
                            guard self.session === connected, self.healthCheck == token else { return }
                            self.healthCheck = nil
                            if let network = network, let final = final, network.id != final.id {
                                self.disconnected(connected); return
                            }
                            if needsIdentity, let network = network, final?.id == network.id {
                                connected.network = network
                                if self.preferences.revisions[network.id, default: 0] == connected.revisions[network.id, default: 0] {
                                    self.remember(network)
                                    self.notice = ""
                                    self.onChange?()
                                    self.onEvent?(["id": connected.id, "phase": "remembered", "message": "\(connected.photoCount) photos"])
                                }
                            }
                        }
                    }
                }
                if needsIdentity { self.health.verify { respond($0.map { _ in () }) } }
                else { self.health.ping(respond) }
            }
        }
    }

    func disconnected(_ connected: Session) {
        guard session === connected else { return }
        session = nil; healthCheck = nil; health.cancel()
        scanGeneration += 1
        nearby = []
        onChange?()
        onEvent?(["id": connected.id, "phase": "disconnected", "message": "Camera disconnected. Check Wi-Fi and connect again."])
    }

    func remember(_ network: CameraNetwork) {
        setCurrent(network, ready: true)
        if !nearby.contains(where: { $0.id == network.id }) { nearby.append(network) }
        preferences.remember(network, at: now())
    }

    func refresh(requestAuthorization: Bool = false) {
        if requestAuthorization {
            authorization.request { [weak self] _ in self?.refresh() }; return
        }
        guard authorization.allowed else {
            nearby = []; currentNetwork = nil
            notice = "Allow GRBrowser in System Settings → Privacy & Security → Location Services to discover Wi-Fi names. Current Wi-Fi connection still works."
            refreshCurrentNetwork()
            onChange?(); return
        }
        guard !scanning, !isConnecting, canConnect() else { return }
        nextDiscovery = now().addingTimeInterval(10)
        scanning = true; scanGeneration += 1
        let generation = scanGeneration
        worker.async {
            let result = Result { try self.wifi.scan() }
            let current = self.wifi.current()
            let ready = self.wifi.ready(on: nil)
            DispatchQueue.main.async {
                self.scanning = false
                guard self.scanGeneration == generation, !self.isConnecting else { return }
                self.setCurrent(current, ready: ready)
                switch result {
                case .success(let networks): self.nearby = networks; self.notice = ""
                case .failure: self.nearby = []; self.notice = "Wi-Fi discovery unavailable. Use Current Wi-Fi or refresh discovery."
                }
                self.onChange?()
            }
        }
    }

    func connect(id: String, target: String?) {
        precondition(Thread.isMainThread)
        guard !isConnecting, canConnect(), !id.isEmpty else { return }
        session = nil; healthCheck = nil; health.cancel()
        scanGeneration += 1
        let bluetoothID = target.flatMap { $0.hasPrefix("bt:") ? UUID(uuidString: String($0.dropFirst(3))) : nil }
        let job = Attempt(id: id, target: bluetoothID == nil ? target : nil, revisions: preferences.revisions)
        job.bluetoothID = bluetoothID; job.selectionRevision = selectionRevision
        job.bluetoothRevision = bluetoothID.map { devices.revisions[$0, default: 0] } ?? 0
        attempt = job; manualRecovery = false
        if let bluetoothID = bluetoothID {
            beginBluetooth(job, id: bluetoothID); return
        }
        if let target = target, !preferences.networks.contains(where: { $0.network.id == target }) {
            finish(job, error: appError("That camera network was forgotten.")); return
        }
        event(job, phase: "preparing", message: "Preparing connection…")
        authorization.request { allowed in
            guard self.isLive(job) else { return }
            self.begin(job, allowed: allowed)
        }
    }

    func begin(_ job: Attempt, allowed: Bool) {
        notice = allowed ? "" : "Wi-Fi names need Location Services access. Current Wi-Fi connection still works."
        if !allowed { nearby = []; currentNetwork = nil }
        onChange?()
        worker.async {
            let initial = allowed ? self.wifi.current() : nil
            let result = Result { () -> CameraNetwork? in
                guard let target = job.target else { return nil }
                guard allowed else { throw appError("Allow Location Services to reconnect, or choose Current Wi-Fi.") }
                guard let network = try self.wifi.scan().first(where: { $0.id == target }) else {
                    throw appError("The selected camera Wi-Fi is no longer nearby.")
                }
                return network
            }
            DispatchQueue.main.async {
                guard self.isLive(job) else { return }
                job.initial = initial
                if let initial = initial { self.setCurrent(initial, ready: true); self.onChange?() }
                switch result {
                case .failure(let error): self.finish(job, error: error)
                case .success(let network):
                    if let network = network, initial?.id != network.id { self.obtainPassword(job, network: network) }
                    else { self.startVerification(job, network: network ?? initial, waitForNetwork: false) }
                }
            }
        }
    }

    enum CredentialSource { case macOS, app, manual }

    func obtainPassword(_ job: Attempt, network: CameraNetwork, source: CredentialSource = .macOS) {
        guard network.secured else { join(job, network: network, password: nil); return }
        guard source != .manual else {
            event(job, phase: "credentials", message: job.lastFailure == nil ? "Waiting for Wi-Fi password…"
                : "Saved password could not connect. Enter the camera Wi-Fi password…")
            passwordPrompt(network.name) { answer in
                guard self.isLive(job) else { return }
                guard let (password, remember) = answer else {
                    self.finish(job, phase: "cancelled", message: "Connection cancelled"); return
                }
                job.pendingPassword = remember ? password : nil
                self.join(job, network: network, password: password)
            }
            return
        }
        event(job, phase: "credentials", message: source == .macOS
            ? "Checking saved macOS Wi-Fi password. Keychain access may need approval…"
            : "Checking GRBrowser's saved Wi-Fi password…")
        let next: CredentialSource = source == .macOS ? .app : .manual
        worker.async {
            let result = Result { try source == .macOS ? self.savedCredentials.password(for: network.id)
                                                     : self.credentials.password(for: network.id) }
            DispatchQueue.main.async {
                guard self.isLive(job) else { return }
                switch result {
                case .failure(SavedWiFiCredentialError.cancelled):
                    self.finish(job, phase: "cancelled", message: "Keychain access cancelled")
                case .failure(let error): self.finish(job, error: error)
                case .success(let password?) where job.triedPasswords.insert(password).inserted:
                    self.join(job, network: network, password: password) {
                        self.obtainPassword(job, network: network, source: next)
                    }
                case .success: self.obtainPassword(job, network: network, source: next)
                }
            }
        }
    }

    func join(_ job: Attempt, network: CameraNetwork, password: String?, fallback: (() -> Void)? = nil) {
        event(job, phase: "joining", message: "Joining \(network.name)…")
        worker.async {
            guard !job.cancellation.isCancelled else { return }
            let result = Result { try self.wifi.join(network, password: password) }
            DispatchQueue.main.async {
                guard self.isLive(job) else { return }
                switch result {
                case .failure(let error):
                    if let fallback = fallback { job.lastFailure = error; fallback() }
                    else { self.finish(job, error: error) }
                case .success:
                    job.lastFailure = nil
                    job.initial = network
                    self.startVerification(job, network: network, waitForNetwork: true)
                }
            }
        }
    }

    func startVerification(_ job: Attempt, network: CameraNetwork?, waitForNetwork: Bool) {
        // User prompts are outside this bounded network/camera readiness interval.
        let deadline = job.deadline ?? now().addingTimeInterval(timeout)
        later(timeout) {
            if self.isLive(job) && !job.verified {
                let fallback = job.waitingForNetwork ? "Wi-Fi joined but its local network did not become ready."
                    : "Camera connection timed out. Check camera Wi-Fi and try again."
                self.finish(job, error: job.lastFailure ?? appError(fallback))
            }
        }
        job.waitingForNetwork = waitForNetwork
        func checkReadiness() {
            guard self.isLive(job) else { return }
            if !waitForNetwork { self.verify(job, deadline: deadline); return }
            self.event(job, phase: "waiting", message: "Waiting for camera Wi-Fi…")
            self.worker.async {
                let ready = self.wifi.ready(on: network)
                DispatchQueue.main.async {
                    guard self.isLive(job) else { return }
                    if ready { self.verify(job, deadline: deadline) }
                    else if self.now() < deadline { self.later(0.25, checkReadiness) }
                    else { self.finish(job, error: appError("Wi-Fi did not become ready.")) }
                }
            }
        }
        checkReadiness()
    }

    func verify(_ job: Attempt, deadline: Date) {
        job.waitingForNetwork = false
        event(job, phase: "camera", message: "Connecting to camera…")
        camera.verify { result in
            guard self.isLive(job) else { return }
            switch result {
            case .failure(let error):
                job.lastFailure = error
                if self.now() < deadline { self.later(0.75) { if self.isLive(job) { self.verify(job, deadline: deadline) } } }
                else { self.finish(job, error: error) }
            case .success(let photos):
                let allowed = self.authorization.allowed
                self.worker.async {
                    let final = allowed ? self.wifi.current() : nil
                    DispatchQueue.main.async {
                        guard self.isLive(job) else { return }
                        guard job.target == nil || final?.id == job.target else {
                            self.finish(job, error: appError("Wi-Fi changed before camera verification finished.")); return
                        }
                        if job.initial == nil, let final = final, self.now() < deadline {
                            job.initial = final
                            self.verify(job, deadline: deadline)
                            return
                        }
                        if let initial = job.initial, let final = final, initial.id != final.id {
                            self.finish(job, error: appError("Wi-Fi changed before camera verification finished.")); return
                        }
                        if let identity = job.bluetoothIdentity, !job.propsVerified {
                            self.camera.identify(identity) { result in
                                guard self.isLive(job) else { return }
                                switch result {
                                case .failure(let error): self.finish(job, error: error)
                                case .success: job.propsVerified = true; self.verify(job, deadline: deadline)
                                }
                            }
                            return
                        }
                        job.verified = true
                        let stable = final != nil && final?.id == job.initial?.id
                        let forgotten = final.map { self.preferences.revisions[$0.id, default: 0] != job.revisions[$0.id, default: 0] } ?? false
                        if stable, !forgotten, let network = final {
                            self.remember(network)
                        }
                        if !stable { job.initial = nil }
                        if stable, !forgotten, let password = job.pendingPassword, let final = final {
                            self.worker.async {
                                guard !job.cancellation.isCancelled else { return }
                                let result = Result { try self.credentials.save(password, for: final.id) }
                                DispatchQueue.main.async {
                                    guard self.isLive(job) else { return }
                                    // Forget can run while a credential write is queued; serialize deletion after it.
                                    if case .failure(let error) = result { self.complete(job, photos: photos, warning: error.localizedDescription) }
                                    else { self.complete(job, photos: photos) }
                                }
                            }
                        } else { self.complete(job, photos: photos) }
                    }
                }
            }
        }
    }

    func complete(_ job: Attempt, photos: [CameraPhoto], warning: String? = nil) {
        var value: [String: Any] = ["photos": photos.map { ["dir": $0.dir, "file": $0.file] }]
        let identityWarning = job.initial == nil ? (authorization.allowed
            ? "Wi-Fi name unavailable; network not remembered yet."
            : "Network not remembered. Allow GRBrowser in System Settings → Privacy & Security → Location Services.") : nil
        if let identityWarning = identityWarning { notice = identityWarning }
        value["warning"] = [warning, identityWarning].compactMap { $0 }.joined(separator: " ")
        finish(job, phase: "completed", message: "\(photos.count) photos", extra: value)
        onChange?()
    }

    func forget(_ id: String) {
        guard preferences.networks.contains(where: { $0.network.id == id }), forgetting.insert(id).inserted else { return }
        preferences.invalidateHistory(for: id)
        onChange?()
        worker.async {
            let result = Result { try self.credentials.remove(id) }
            DispatchQueue.main.async {
                self.forgetting.remove(id)
                switch result {
                case .success: self.preferences.forget(id); self.devices.unlink(id)
                case .failure(let error): self.notice = error.localizedDescription
                }
                self.onChange?()
            }
        }
    }

    func settingsValue() -> [String: Any] {
        var value: [String: Any] = ["folder": preferences.folder()?.path ?? "", "format": preferences.format.rawValue,
         "networks": preferences.networks.map { ["id": $0.network.id, "name": $0.network.name,
             "lastConnected": $0.lastConnected.timeIntervalSince1970, "forgetting": forgetting.contains($0.network.id)] },
         "available": nearby.map { $0.id }, "current": currentID ?? "", "notice": notice,
         "currentName": currentNetwork?.name ?? "", "wifiConnected": wifiReady.map { $0 as Any } ?? NSNull(),
         "discoveryAllowed": authorization.allowed]
        value.merge(bluetoothSettings()) { _, new in new }
        return value
    }

    func event(_ job: Attempt, phase: String, message: String) {
        guard isLive(job) else { return }
        onEvent?(["id": job.id, "phase": phase, "message": message])
    }
    func finish(_ job: Attempt, error: Error) { finish(job, phase: "failed", message: error.localizedDescription) }
    func finish(_ job: Attempt, phase: String, message: String, extra: [String: Any] = [:]) {
        guard isLive(job) else { return }
        job.terminal = phase; camera.cancel()
        if phase != "completed" { job.cancellation.cancel() }
        job.pendingPassword = nil; job.triedPasswords.removeAll(); job.bluetoothCredentials = nil
        if phase != "completed", job.bluetoothID != nil { manualRecovery = true }
        onEvent?(["id": job.id, "phase": "draining", "finishing": phase == "completed", "message": phase == "completed" ? "Finishing connection…" : "Cancelling… Waiting for pending network operations."])
        onChange?()
        let drained = DispatchGroup()
        drained.enter(); worker.async { drained.leave() }
        if job.bluetoothID != nil {
            drained.enter()
            bluetooth.release { drained.leave() }
        }
        drained.notify(queue: .main) {
            guard self.attempt === job else { return }
            if let id = job.bluetoothID { self.releasedBluetooth = id }
            self.attempt = nil
            if phase == "completed" {
                let count = (extra["photos"] as? [[String: String]])?.count ?? 0
                self.session = Session(job: job, photoCount: count)
                if let id = job.bluetoothID, self.devices.revisions[id, default: 0] == job.bluetoothRevision {
                    let linked = job.initial.flatMap { self.preferences.revisions[$0.id, default: 0] == job.revisions[$0.id, default: 0] ? $0.id : nil }
                    self.devices.succeeded(id, network: linked, at: self.now())
                }
            }
            var value = extra
            value.merge(["id": job.id, "phase": phase, "message": message]) { _, new in new }
            self.onEvent?(value); self.onChange?(); self.refreshCurrentNetwork()
        }
    }
}

// MARK: - Download Handler
// Receives download requests from JS, fetches from camera, saves via NSSavePanel

class DownloadHandler: NSObject, WKScriptMessageHandler, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var webView: WKWebView?
    let preferences: AppPreferences
    var canStart: () -> Bool = { true }
    var isDownloading: Bool { activeRequestID != nil }
    // Main-thread admission guard also rejects requests queued during a disk write.
    private var activeRequestID: String?

    // Operation state and delegate callbacks are confined to this serial queue.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let cameraBase: URL
    private let temporaryDirectory: URL
    private let archiveExecutable: URL
    private var session: URLSession?
    private var operation: DownloadOperation?
    private var currentTask: URLSessionDownloadTask?

    private final class DownloadOperation {
        let id: String
        let files: [String]
        let directory: URL
        let format: ExportFormat
        var destination: URL?
        var stagedFiles: [URL] = []
        var photosDirectory: URL { directory.appendingPathComponent("Photos", isDirectory: true) }
        var completed = 0
        var phase = "preparing"
        var lastProgressTime = Date.distantPast
        var stagedFile: URL?
        var filename: String { (files[min(completed, files.count - 1)] as NSString).lastPathComponent }

        init(id: String, files: [String], directory: URL, format: ExportFormat) {
            self.id = id
            self.files = files
            self.directory = directory
            self.format = format
        }
    }

    init(preferences: AppPreferences = AppPreferences(), cameraBase: URL = URL(string: CAMERA_BASE)!,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         archiveExecutable: URL = URL(fileURLWithPath: "/usr/bin/ditto")) {
        self.preferences = preferences
        self.cameraBase = cameraBase
        self.temporaryDirectory = temporaryDirectory
        self.archiveExecutable = archiveExecutable
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let files = json["files"] as? [String] else { return }
        startDownload(id: id, files: files)
    }

    func startDownload(id: String, files: [String]) {
        precondition(Thread.isMainThread)
        guard activeRequestID == nil, canStart(), !id.isEmpty, !files.isEmpty else { return }
        activeRequestID = id
        let format = preferences.format
        queue.addOperation {
            let job = DownloadOperation(id: id, files: files,
                directory: self.temporaryDirectory.appendingPathComponent("GRBrowser-\(UUID().uuidString)"), format: format)
            self.operation = job
            self.emit(job, phase: "preparing")
            DispatchQueue.main.async { self.resolveDestination(job) }
        }
    }

    private func downloadNext(_ job: DownloadOperation) {
        let file = job.files[job.completed]
        let url = cameraBase.appendingPathComponent("v1/photos").appendingPathComponent(file)
        var request = URLRequest(url: url)
        request.setValue("GRBrowser/1.0", forHTTPHeaderField: "User-Agent")
        currentTask = session?.downloadTask(with: request)
        job.stagedFile = nil
        job.lastProgressTime = .distantPast
        emit(job, phase: "downloading")
        currentTask?.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard downloadTask === currentTask, let job = operation else { return }
        let now = Date()
        guard now.timeIntervalSince(job.lastProgressTime) >= 0.1 else { return }
        job.lastProgressTime = now
        let fraction: Double? = totalBytesExpectedToWrite > 0
            ? min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))) : nil
        let overall = fraction.map { (Double(job.completed) + $0) / Double(job.files.count) }
        emit(job, phase: "downloading", fraction: overall)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard downloadTask === currentTask, let job = operation else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
                throw failure("Camera returned HTTP \(status)")
            }
            let destination = job.photosDirectory.appendingPathComponent(job.files[job.completed])
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            // URLSession removes its temporary file when this delegate callback returns.
            try FileManager.default.moveItem(at: location, to: destination)
            job.stagedFile = destination
        } catch {
            finish(job, phase: "failed", message: "Download failed (\(job.filename)): \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === currentTask, let job = operation else { return }
        if let error = error {
            finish(job, phase: "failed", message: "Download failed (\(job.filename)): \(error.localizedDescription)")
            return
        }
        guard let stagedFile = job.stagedFile else {
            finish(job, phase: "failed", message: "Download failed: no file received")
            return
        }
        let filename = job.filename
        job.stagedFiles.append(stagedFile)
        job.completed += 1
        emit(job, phase: "downloading", fraction: Double(job.completed) / Double(job.files.count),
             filename: filename)
        currentTask = nil
        if job.completed < job.files.count {
            downloadNext(job)
        } else {
            prepareSave(job)
        }
    }

    private func prepareSave(_ job: DownloadOperation) {
        var saved = 0
        do {
            guard let directory = job.destination else { throw failure("No download folder selected") }
            let sources: [URL]
            if job.files.count > 1 && job.format == .zip {
                emit(job, phase: "archiving")
                let archive = job.directory.appendingPathComponent("GRIIIx_\(dateStr()).zip")
                do { try createArchive(photos: job.photosDirectory, destination: archive) }
                catch { throw failure("ZIP failed: \(error.localizedDescription)") }
                sources = [archive]
            } else { sources = job.stagedFiles }
            emit(job, phase: "saving")
            var lastName = ""
            for source in sources {
                let output = try publishFile(source, in: directory)
                lastName = output.lastPathComponent
                saved += 1
            }
            let description = sources.count == 1 ? lastName : "\(saved) photos"
            finish(job, phase: "completed", message: "Saved: \(description)")
        } catch {
            let total = job.format == .zip && job.files.count > 1 ? 1 : job.files.count
            finish(job, phase: "failed", message: "Save failed (\(saved)/\(total) saved): \(error.localizedDescription)")
        }
    }

    // Copy beside the destination, then atomically rename with exclusive creation.
    // RENAME_EXCL protects both existing files and races with other writers.
    func publishFile(_ source: URL, in directory: URL) throws -> URL {
        var template = Array(directory.appendingPathComponent(".GRBrowser-XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let temporary = URL(fileURLWithPath: String(cString: template))
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.close()
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var suffix = 0
        while true {
            let name = suffix == 0 ? source.lastPathComponent
                : "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
            let destination = directory.appendingPathComponent(name)
            let result = temporary.path.withCString { from in
                destination.path.withCString { to in renamex_np(from, to, UInt32(RENAME_EXCL)) }
            }
            if result == 0 { return destination }
            let code = errno
            guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
            suffix += 1
        }
    }

    private func resolveDestination(_ job: DownloadOperation) {
        func begin(_ directory: URL) {
            self.queue.addOperation {
                guard self.operation === job else { return }
                job.destination = directory
                do {
                    guard job.files.allSatisfy({ file in
                        !file.hasPrefix("/") && file.split(separator: "/", omittingEmptySubsequences: false)
                            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
                    }) else { throw self.failure("Invalid camera file path") }
                    try FileManager.default.createDirectory(at: job.photosDirectory, withIntermediateDirectories: true)
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.timeoutIntervalForRequest = 30
                    configuration.timeoutIntervalForResource = 600
                    self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: self.queue)
                    self.downloadNext(job)
                } catch {
                    self.finish(job, phase: "failed", message: "Download failed: \(error.localizedDescription)")
                }
            }
        }
        if let directory = preferences.folder(), AppPreferences.usableFolder(directory) {
            begin(directory)
        } else {
            chooseDirectory { directory in
                guard let directory = directory else {
                    self.queue.addOperation { self.finish(job, phase: "cancelled", message: "Cancelled") }
                    return
                }
                do { try self.preferences.setFolder(directory); begin(directory) }
                catch {
                    self.queue.addOperation {
                        self.finish(job, phase: "failed", message: "Folder unavailable: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func chooseDirectory(completion: @escaping (URL?) -> Void) {
        pickDownloadFolder(window: webView?.window, initial: preferences.folder(), completion: completion)
    }

    // These boundary methods also allow tests to inject save and filesystem failures.
    func createArchive(photos: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = archiveExecutable
        process.arguments = ["-c", "-k", "--keepParent", photos.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let size = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber,
              size.int64Value > 0 else { throw failure("Could not create the photo archive") }
        let archive = try FileHandle(forReadingFrom: destination)
        defer { try? archive.close() }
        guard try archive.read(upToCount: 4) == Data([0x50, 0x4b, 0x03, 0x04]) else {
            throw failure("Invalid photo archive")
        }
    }

    private func emit(_ job: DownloadOperation, phase: String, fraction: Double? = nil,
                      filename: String? = nil, message: String? = nil) {
        job.phase = phase
        var event: [String: Any] = ["id": job.id, "phase": phase, "completed": job.completed,
                                    "total": job.files.count, "filename": filename ?? job.filename]
        event["fraction"] = fraction
        event["message"] = message
        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            if ["completed", "failed", "cancelled"].contains(phase), self.activeRequestID == job.id {
                self.activeRequestID = nil
            }
            self.deliverEvent(json: json)
        }
    }

    func deliverEvent(json: String) {
        webView?.evaluateJavaScript("_downloadEvent(\(json))")
    }

    private func finish(_ job: DownloadOperation, phase: String, message: String) {
        guard operation === job else { return }
        session?.invalidateAndCancel()
        session = nil
        currentTask = nil
        try? FileManager.default.removeItem(at: job.directory)
        operation = nil
        emit(job, phase: phase, message: message)
    }

    private func failure(_ message: String) -> Error {
        NSError(domain: "GRBrowser.Download", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private func dateStr() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

// MARK: - Settings and connection bridge

final class SettingsPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w", attachedSheet == nil {
            performClose(nil); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        if attachedSheet == nil { performClose(sender) }
    }
}

private final class WeakSettingsHandler: NSObject, WKScriptMessageHandler {
    weak var target: AppController?
    init(_ target: AppController) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private let onClose: () -> Void
    private var contentReady = false
    private var presentationRequested = false
    private var pendingPresentation: (() -> Void)?
    init(handler: AppController) {
        onClose = { [weak handler] in handler?.webView?.evaluateJavaScript("_settingsClosed()") }
        let config = WKWebViewConfiguration()
        config.userContentController.add(WeakSettingsHandler(handler), name: "app")
        webView = WKWebView(frame: .zero, configuration: config)
        let panel = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Settings"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 400, height: 360)
        panel.contentView = webView
        panel.initialFirstResponder = webView
        super.init(window: panel)
        panel.delegate = self
        webView.navigationDelegate = self
        webView.loadHTMLString(SETTINGS_HTML, baseURL: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        contentReady = true
        let presentation = pendingPresentation
        pendingPresentation = nil
        presentation?()
    }

    func present(relativeTo parent: NSWindow?, settings: [String: Any]) {
        guard !presentationRequested, let window = window, NSApplication.shared.modalWindow == nil,
              let data = try? JSONSerialization.data(withJSONObject: settings),
              let json = String(data: data, encoding: .utf8) else { return }
        presentationRequested = true
        let presentation = { [weak self, weak parent] in
            guard let self = self else { return }
            // Measure the populated form at its opening width, including body padding.
            window.setContentSize(NSSize(width: 480, height: 540))
            self.webView.evaluateJavaScript("_settingsChanged(\(json)); settingsContentHeight()") { [weak self, weak parent] value, _ in
                guard let height = value as? Double else {
                    self?.presentationRequested = false
                    return
                }
                // Enter the modal loop after the WebKit callback has returned.
                RunLoop.main.perform { [weak self, weak parent] in
                    self?.presentSized(relativeTo: parent, contentHeight: height)
                }
            }
        }
        if contentReady { presentation() } else { pendingPresentation = presentation }
    }

    private func presentSized(relativeTo parent: NSWindow?, contentHeight: Double) {
        defer { presentationRequested = false }
        guard let window = window, NSApplication.shared.modalWindow == nil,
              let screen = parent?.screen ?? window.screen ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let titleBarHeight = window.frame.height - window.contentLayoutRect.height
        window.setContentSize(NSSize(width: 480, height: min(max(360, contentHeight), visibleFrame.height - titleBarHeight)))
        window.center()
        if let parent = parent {
            window.setFrameOrigin(NSPoint(x: parent.frame.midX - window.frame.width / 2,
                                          y: parent.frame.midY - window.frame.height / 2))
        }
        // Keep the full window on screen when its parent is near an edge.
        window.setFrameOrigin(NSPoint(x: max(visibleFrame.minX, min(window.frame.minX, visibleFrame.maxX - window.frame.width)),
                                      y: max(visibleFrame.minY, min(window.frame.minY, visibleFrame.maxY - window.frame.height))))
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.runModal(for: window)
        window.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
        onClose()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.attachedSheet == nil }
    func windowWillClose(_ notification: Notification) {
        if NSApplication.shared.modalWindow === window { NSApplication.shared.stopModal() }
    }
}

final class AppController: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    let preferences: AppPreferences
    let connection: CameraConnection
    private let download: DownloadHandler
    private var choosingFolder = false
    private var connectionTimer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private(set) var settingsController: SettingsWindowController?
    private var settingsScheduled = false

    init(preferences: AppPreferences, download: DownloadHandler, connection: CameraConnection? = nil) {
        self.preferences = preferences
        self.download = download
        self.connection = connection ?? CameraConnection(preferences: preferences)
        super.init()
        preferences.onChange = { [weak self] in self?.pushSettings() }
        self.connection.onChange = { [weak self] in self?.pushSettings() }
        self.connection.onEvent = { [weak self] in self?.send("_connectionEvent", value: $0) }
        self.connection.canConnect = { [weak download] in download?.isDownloading == false }
        download.canStart = { [weak connected = self.connection] in connected?.isConnecting == false }
        self.connection.passwordPrompt = { [weak self] name, completion in
            self?.promptPassword(for: name, completion: completion)
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.connection.poll(discover: NSApplication.shared.isActive)
        }
        connectionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.connection.computerWillSleep() }
    }
    deinit {
        connectionTimer?.invalidate()
        if let observer = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    func send(_ function: String, value: [String: Any], to target: WKWebView? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let json = String(data: data, encoding: .utf8) else { return }
        (target ?? webView)?.evaluateJavaScript("\(function)(\(json))")
    }
    func pushSettings() {
        let value = connection.settingsValue()
        send("_settingsChanged", value: value)
        if let settingsWeb = settingsController?.webView { send("_settingsChanged", value: value, to: settingsWeb) }
    }
    func showSettings() {
        guard !settingsScheduled, NSApplication.shared.modalWindow == nil, webView?.window?.attachedSheet == nil else { return }
        if settingsController == nil { settingsController = SettingsWindowController(handler: self) }
        settingsScheduled = true
        // Enter AppKit's modal loop from the run loop, after the WebKit/main-queue callback returns.
        // This keeps asynchronous preference, network, and download updates running in the modal.
        RunLoop.main.perform { [weak self] in
            guard let self = self else { return }
            self.settingsScheduled = false
            guard NSApplication.shared.modalWindow == nil, self.webView?.window?.attachedSheet == nil else { return }
            self.pushSettings()
            self.connection.refresh()
            self.settingsController?.present(relativeTo: self.webView?.window, settings: self.connection.settingsValue())
        }
    }
    private func showError(_ error: Error) {
        guard let data = try? JSONSerialization.data(withJSONObject: [error.localizedDescription]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("_appError(\(json)[0])")
        settingsController?.webView.evaluateJavaScript("_appError(\(json)[0])")
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        switch action {
        case "ready": pushSettings(); connection.refresh(requestAuthorization: true)
        case "settingsReady": pushSettings()
        case "openSettings": showSettings()
        case "closeSettings": settingsController?.window?.performClose(nil)
        case "settings": pushSettings(); connection.refresh()
        case "discover": connection.refresh(requestAuthorization: true)
        case "format":
            if let raw = body["value"] as? String, let format = ExportFormat(rawValue: raw) {
                preferences.setFormat(format)
            }
        case "folder":
            let parent = message.webView?.window ?? webView?.window
            guard !choosingFolder, parent?.attachedSheet == nil else { return }
            choosingFolder = true
            pickDownloadFolder(window: parent, initial: preferences.folder()) { url in
                self.choosingFolder = false
                if let url = url {
                    do { try self.preferences.setFolder(url) } catch { self.showError(error) }
                }
                self.pushSettings()
            }
        case "forget": if let id = body["id"] as? String { connection.forget(id) }
        case "findBluetooth": connection.findBluetooth()
        case "selectTarget": if let target = body["target"] as? String { connection.selectTarget(target) }
        case "forgetBluetooth": if let id = body["id"] as? String { connection.forgetBluetooth(id) }
        case "cancelConnection": connection.cancelConnection()
        case "disconnect": connection.disconnectSession()
        case "connect":
            if let id = body["id"] as? String {
                let target = body["target"] as? String ?? ""
                connection.connect(id: id, target: target.isEmpty ? nil : target)
            }
        default: break
        }
    }
    private func promptPassword(for name: String, completion: @escaping ((String, Bool)?) -> Void) {
        let parent = settingsController?.window?.isVisible == true ? settingsController?.window : webView?.window
        guard parent?.attachedSheet == nil else { completion(nil); return }
        let alert = NSAlert()
        alert.messageText = "Join \(name)"
        alert.informativeText = "Enter the camera Wi-Fi password. Your Mac will switch to this network."
        alert.addButton(withTitle: "Join")
        alert.addButton(withTitle: "Cancel")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 65))
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 35, width: 300, height: 24))
        field.placeholderString = "Wi-Fi password"
        field.setAccessibilityLabel("Camera Wi-Fi password")
        let remember = NSButton(checkboxWithTitle: "Remember password in Keychain", target: nil, action: nil)
        remember.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        remember.state = .off
        view.addSubview(field); view.addSubview(remember)
        alert.accessoryView = view
        alert.window.initialFirstResponder = field
        let respond: (NSApplication.ModalResponse) -> Void = { response in
            let answer = response == .alertFirstButtonReturn ? (field.stringValue, remember.state == .on) : nil
            field.stringValue = ""
            completion(answer)
        }
        if let window = parent { alert.beginSheetModal(for: window, completionHandler: respond) }
        else { respond(alert.runModal()) }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let schemeHandler = CameraSchemeHandler()
    let preferences = AppPreferences()
    lazy var downloadHandler = DownloadHandler(preferences: preferences)
    lazy var controller = AppController(preferences: preferences, download: downloadHandler)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "gr-cam")
        config.userContentController.add(downloadHandler, name: "download")
        config.userContentController.add(controller, name: "app")

        // Allow mixed content and local resource loading
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true  // Enable Safari Web Inspector for debugging
        downloadHandler.webView = webView
        controller.webView = webView
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit GRBrowser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        NSApplication.shared.mainMenu = menu

        // Window
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let w: CGFloat = min(1200, screenRect.width * 0.85)
        let h: CGFloat = min(800, screenRect.height * 0.85)
        let x = screenRect.midX - w / 2
        let y = screenRect.midY - h / 2

        window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: w, height: h),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GR IIIx Browser"
        window.contentView = webView
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
        window.minSize = NSSize(width: 480, height: 360)
        window.makeKeyAndOrderFront(nil)

        // Load HTML
        webView.loadHTMLString(APP_HTML, baseURL: nil)
    }

    @objc func showSettings() { controller.showSettings() }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller.connection.refreshCurrentNetwork()
        controller.connection.checkConnection()
        controller.connection.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
