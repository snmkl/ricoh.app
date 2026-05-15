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
  .dl-prog { font-family: var(--mono); font-size: 10px; color: var(--accent); }
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
    <button onclick="dlSelected()" id="dlBtn" disabled>Download</button>
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
    <button onclick="dlCurrent()">↓ FULL RES</button>
    <button onclick="closeLb()">CLOSE</button>
  </div>
</div>

<div class="sel-bar" id="selBar" style="display:none">
  <span id="selCnt">0</span>
  <button onclick="dlSelected()" class="primary">↓ Download</button>
  <button onclick="clearSel()">Clear</button>
  <span class="dl-prog" id="prog"></span>
</div>

<div class="toast" id="toast"></div>

<script>
const API = 'gr-cam://camera';
let photos = [], sel = new Set(), lbIdx = 0;

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
  document.getElementById('dlBtn').disabled = sel.size === 0;
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
  window.webkit.messageHandlers.download.postMessage(JSON.stringify({
    files: [`${p.dir}/${p.file}`]
  }));
}

function dlSelected() {
  const paths = photos.filter(p => sel.has(key(p))).map(p => `${p.dir}/${p.file}`);
  if (paths.length === 0) return;
  document.getElementById('prog').textContent = `Downloading ${paths.length}...`;
  window.webkit.messageHandlers.download.postMessage(JSON.stringify({ files: paths }));
}

// Called from Swift when download completes
function _dlDone(msg) {
  document.getElementById('prog').textContent = '';
  toast(msg);
}
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

class DownloadHandler: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [String] else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            self.downloadFiles(files)
        }
    }

    private func downloadFiles(_ files: [String]) {
        if files.count == 1 {
            // Single file: save directly
            guard let file = files.first,
                  let url = URL(string: "\(CAMERA_BASE)/v1/photos/\(file)"),
                  let data = try? Data(contentsOf: url) else {
                notifyJS("Download failed")
                return
            }
            let filename = (file as NSString).lastPathComponent
            DispatchQueue.main.async {
                self.saveFile(data: data, suggestedName: filename)
            }
        } else {
            // Multiple files: zip them
            let tempDir = FileManager.default.temporaryDirectory
            let zipURL = tempDir.appendingPathComponent("GRIIIx_\(dateStr()).zip")

            // Use /usr/bin/ditto or write a simple zip via Process
            // But simplest: write files to temp dir, then zip
            let workDir = tempDir.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

            var count = 0
            for file in files {
                guard let url = URL(string: "\(CAMERA_BASE)/v1/photos/\(file)"),
                      let data = try? Data(contentsOf: url) else { continue }
                let filename = (file as NSString).lastPathComponent
                let dest = workDir.appendingPathComponent(filename)
                try? data.write(to: dest)
                count += 1
                print("  Fetched [\(count)/\(files.count)] \(filename)")
            }

            // Zip using ditto (available on all macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--keepParent", workDir.path, zipURL.path]
            try? process.run()
            process.waitUntilExit()

            // Cleanup temp files
            try? FileManager.default.removeItem(at: workDir)

            guard FileManager.default.fileExists(atPath: zipURL.path) else {
                notifyJS("Zip failed")
                return
            }

            let zipData = try? Data(contentsOf: zipURL)
            try? FileManager.default.removeItem(at: zipURL)

            DispatchQueue.main.async {
                if let zipData = zipData {
                    self.saveFile(data: zipData, suggestedName: "GRIIIx_\(dateStr()).zip")
                }
            }
        }
    }

    private func saveFile(data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                notifyJS("Saved: \(url.lastPathComponent)")
            } catch {
                notifyJS("Save failed: \(error.localizedDescription)")
            }
        } else {
            notifyJS("Cancelled")
        }
    }

    private func notifyJS(_ msg: String) {
        DispatchQueue.main.async {
            let escaped = msg.replacingOccurrences(of: "'", with: "\\'")
            self.webView?.evaluateJavaScript("_dlDone('\(escaped)')")
        }
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
