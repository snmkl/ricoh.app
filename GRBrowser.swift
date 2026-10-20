import Cocoa
import WebKit
import UniformTypeIdentifiers

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
    padding: 14px 20px;
    display: flex; align-items: center; justify-content: space-between;
    position: sticky; top: 0; background: var(--bg); z-index: 100;
    -webkit-app-region: drag;
  }
  header button, header input { -webkit-app-region: no-drag; }

  .logo {
    font-family: var(--mono); font-weight: 600; font-size: 13px;
    letter-spacing: 0.06em; display: flex; align-items: center; gap: 10px;
  }
  .logo-dot {
    width: 8px; height: 8px; border-radius: 50%;
    background: var(--red); transition: background 0.3s;
  }
  .logo-dot.connected { background: var(--green); }

  .controls { display: flex; gap: 6px; align-items: center; }

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
    <button class="primary" id="connBtn" onclick="doConnect()">CONNECT</button>
  </div>
</header>

<div class="status-bar">
  <span id="status">Not connected</span>
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
let downloadId = null, downloadSequence = 0;

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

async function doConnect() {
  const btn = document.getElementById('connBtn');
  btn.disabled = true; btn.textContent = '...';
  try {
    const ping = await fetch(`${API}/v1/ping`);
    if (!ping.ok) throw new Error('Ping failed');

    const res = await fetch(`${API}/v1/photos`);
    const data = await res.json();
    console.log('Raw:', data);

    photos = [];
    if (data.dirs) {
      for (const d of data.dirs)
        for (const f of (d.files || [])) {
          const name = typeof f === 'string' ? f : f.name;
          photos.push({ dir: d.name, file: name });
        }
    } else if (Array.isArray(data)) {
      for (const i of data)
        photos.push({ dir: i.dir || i.directory || '', file: i.name || i.file });
    }

    photos.sort((a, b) => b.file.localeCompare(a.file));
    document.getElementById('dot').classList.add('connected');
    document.getElementById('status').textContent = `${photos.length} photos`;
    document.getElementById('selAllBtn').disabled = false;
    document.getElementById('empty').style.display = 'none';
    render();
    toast(`${photos.length} photos`);
  } catch (e) {
    console.error(e);
    toast(`Failed: ${e.message}`);
    document.getElementById('status').textContent = 'Connection failed';
  }
  btn.disabled = false; btn.textContent = 'CONNECT';
}

function thumb(p) { return `${API}/v1/photos/${p.dir}/${p.file}?size=thumb`; }
function view(p)  { return `${API}/v1/photos/${p.dir}/${p.file}?size=view`; }
function full(p)  { return `${API}/v1/photos/${p.dir}/${p.file}`; }
function key(p)   { return `${p.dir}/${p.file}`; }

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
  document.querySelectorAll('[data-download]').forEach(button => {
    button.disabled = downloadId !== null ||
      (button.dataset.download === 'selection' ? sel.size === 0 : !photos[lbIdx]);
  });
}

function startDownload(files) {
  if (downloadId !== null || files.length === 0) return;
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
  const stages = { preparing: 'Preparing download…', downloading: 'Downloading…',
    archiving: 'Creating ZIP…', 'awaiting-save': 'Waiting for save location…', saving: 'Saving…' };
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
</script>
</body>
</html>
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

// MARK: - Download Handler
// Receives download requests from JS, fetches from camera, saves via NSSavePanel

class DownloadHandler: NSObject, WKScriptMessageHandler, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var webView: WKWebView?
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
        var photosDirectory: URL { directory.appendingPathComponent("Photos", isDirectory: true) }
        var completed = 0
        var phase = "preparing"
        var lastProgressTime = Date.distantPast
        var stagedFile: URL?
        var filename: String { (files[min(completed, files.count - 1)] as NSString).lastPathComponent }

        init(id: String, files: [String], directory: URL) {
            self.id = id
            self.files = files
            self.directory = directory
        }
    }

    init(cameraBase: URL = URL(string: CAMERA_BASE)!,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         archiveExecutable: URL = URL(fileURLWithPath: "/usr/bin/ditto")) {
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
        guard activeRequestID == nil, !id.isEmpty, !files.isEmpty else { return }
        activeRequestID = id
        queue.addOperation {
            guard self.operation == nil else { return }
            let job = DownloadOperation(id: id, files: files,
                directory: self.temporaryDirectory.appendingPathComponent("GRBrowser-\(UUID().uuidString)"))
            self.operation = job
            self.emit(job, phase: "preparing")
            do {
                guard files.allSatisfy({ file in
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
        job.completed += 1
        emit(job, phase: "downloading", fraction: Double(job.completed) / Double(job.files.count),
             filename: filename)
        currentTask = nil
        if job.completed < job.files.count {
            downloadNext(job)
        } else {
            prepareSave(job, singleFile: stagedFile)
        }
    }

    private func prepareSave(_ job: DownloadOperation, singleFile: URL) {
        do {
            let source: URL
            if job.files.count == 1 {
                source = singleFile
            } else {
                emit(job, phase: "archiving")
                source = job.directory.appendingPathComponent("GRIIIx_\(dateStr()).zip")
                try createArchive(photos: job.photosDirectory, destination: source)
            }
            emit(job, phase: "awaiting-save")
            DispatchQueue.main.async {
                self.chooseDestination(suggestedName: source.lastPathComponent) { destination in
                    self.queue.addOperation {
                        guard self.operation === job else { return }
                        guard let destination = destination else {
                            self.finish(job, phase: "cancelled", message: "Cancelled")
                            return
                        }
                        self.emit(job, phase: "saving")
                        do {
                            // Map large files when possible; keep disk I/O off the UI thread.
                            try Data(contentsOf: source, options: .mappedIfSafe).write(to: destination, options: .atomic)
                            self.finish(job, phase: "completed", message: "Saved: \(destination.lastPathComponent)")
                        } catch {
                            self.finish(job, phase: "failed", message: "Save failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        } catch {
            finish(job, phase: "failed", message: "ZIP failed: \(error.localizedDescription)")
        }
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

    func chooseDestination(suggestedName: String, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        let respond: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .OK ? panel.url : nil)
        }
        if let window = webView?.window {
            panel.beginSheetModal(for: window, completionHandler: respond)
        } else {
            panel.begin(completionHandler: respond)
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

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    let schemeHandler = CameraSchemeHandler()
    let downloadHandler = DownloadHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: "gr-cam")
        config.userContentController.add(downloadHandler, name: "download")

        // Allow mixed content and local resource loading
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true  // Enable Safari Web Inspector for debugging
        downloadHandler.webView = webView

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
