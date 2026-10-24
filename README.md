# GR IIIx Browser

A native macOS app to browse and download photos from your Ricoh GR IIIx over Wi-Fi. No phone app needed.

## How it works

The GR IIIx runs a small HTTP server on `192.168.0.1:80` when Wi-Fi is enabled. The official Ricoh GR app is just a client for this API. This app does the same thing, but on your laptop.

SwiftUI renders the browser and Settings inside AppKit windows. Camera verification,
image loading, and original downloads use independent `URLSession` policies. No web
view or proxy server is required. Thumbnail and preview requests share a two-request
scheduler and a 64 MiB decoded-image cache; thumbnails are downsampled in memory.

## Requirements

- macOS 13.3 or later (Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`) for building
- Python 3 for the shared build helper and fixture runner

## Build & Run

```sh
./build.sh
open build/GRBrowser.app
```

Run `./build.sh install` to build and install in `~/Applications`.

For development:

```
make run
```

Binary lands in `build/GRBrowser`.

## Usage

1. Turn on Wi-Fi on your GR IIIx (Menu → Wireless → Wi-Fi)
2. Connect your Mac to the camera's network (SSID shown on camera screen)
3. Open the app, select **Current Wi-Fi**, and hit **CONNECT**
4. Browse the grid or list, click a photo to preview, and use checkboxes to select photos.
5. Use **Select all**, **Clear selection** (the circled ×), or **Download**. Batches follow displayed order.

Preview provides previous/next and **Download original**. Left/Right and Escape work
when preview owns keyboard focus; click its image to return keyboard focus there.
Closing preview returns focus to the active gallery photo. Browsing and selection
remain available during exports, with shared progress above the preview. Failed
images have a placeholder and a **Retry image** context-menu action.

Command-click anywhere on a photo (including its checkbox) to toggle it without
opening preview. Shift-click selects the inclusive range from the last clicked or
keyboard-focused photo, following displayed order across camera directories.
Shift takes precedence when Command is also held.

With the gallery focused, use **Shift+Arrow** to extend or shrink that range. Left
and Right follow photo order; Up and Down move by the current grid row, or by one
photo in list view. Reversing direction contracts the range and can cross its
anchor. Independent selections made before the range remain selected, even when
it shrinks. Releasing Shift preserves the range for later adjustment.

The white inset outline marks the active photo; blue marks selected membership.
Closing preview restores gallery focus. Switching grid/list or resizing preserves
the range. **Clear selection** and **Select all/Deselect all** start a fresh range
from the retained active photo. Plain-click still opens preview, and an unmodified
checkbox toggles only its photo.

### Connect via Bluetooth

Bluetooth handoff remains experimental. Automated protocol and fixture checks pass;
physical pairing, camera firmware behavior, and AP stability still require camera
validation. Manual Current Wi-Fi access remains available.

1. Enable camera Bluetooth, enter Pairing, and set its Action Mode to **On anytime** if you want to connect while the body is off.
2. Choose **Find cameras…** in the app and allow Bluetooth access. Select your camera in the connection selector.
3. Press **CONNECT** and complete any macOS pairing/passkey prompt. Keep Mac Wi-Fi enabled and allow Location Services for automatic camera-network joining.

On later connections, select the remembered camera and press **CONNECT**. The app wakes the camera when needed, enables its Wi-Fi and loads your photos. The selector's Bluetooth/Wi-Fi icon identifies the selected connection route. **Released** means Bluetooth setup has finished; browsing and downloads continue over Wi-Fi.

The app uses your Mac's **Computer Name** as the camera's paired-device label where supported. Renaming the Mac updates that label on the next Bluetooth connection.

Joining the camera's Wi-Fi may interrupt your Mac's internet connection. **CANCEL** stops setup, but camera power or Wi-Fi may already have changed. **DISCONNECT** closes the library without turning off the camera or returning your Mac to its previous network.

### Settings

Open **Settings** (⌘,) to choose the download folder and batch format. Downloads
save directly to that folder. Nearby remembered camera networks appear in the
selector; select one to join its Wi-Fi before connecting to the camera.
Remove remembered networks with **Forget** in Settings. **Forget camera** removes
only the app's Bluetooth history; it leaves macOS pairing and Wi-Fi history intact.
Settings is a reusable native modal with a scrollable form and independent device
lists. Close it with its title-bar button, Command-W, or Escape. Its folder picker
attaches as a sheet; closing Settings leaves active exports running.

## API Endpoints

Discovered via firmware reverse engineering ([source](https://notes.secretsauce.net/notes/2022/06/16_ricoh-gr-iiix-80211-reverse-engineering.html)):

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/v1/ping` | Health check |
| GET | `/v1/photos` | List all photos |
| GET | `/v1/photos/{dir}/{file}` | Download full-res image |
| GET | `/v1/photos/{dir}/{file}?size=thumb` | Thumbnail |
| GET | `/v1/photos/{dir}/{file}?size=view` | Medium preview |
| GET | `/v1/photos/{dir}/{file}/info` | EXIF/metadata |
| GET | `/v1/props` | Camera properties |
| GET | `/v1/liveview` | MJPEG live view stream |
| POST | `/v1/camera/shoot` | Trigger shutter |

## Troubleshooting

**Connection failed** — Make sure you're connected to the camera's Wi-Fi network, not your regular network. The camera IP is `192.168.0.1` by default.

**Empty grid** — An empty camera library shows “No photos on this camera.” Invalid or unavailable photo lists show a connection error. Include the displayed error and camera model/firmware when reporting an issue.

**Camera not found over Bluetooth** — Check that camera Bluetooth is enabled, move it closer, and disconnect any phone app using it. Use **On anytime** for connection while the camera is off.

**Pairing or automatic connection failed** — Follow the camera's pairing instructions and complete the macOS passkey prompt. Check Mac Bluetooth, Wi-Fi and Location Services permissions. If the camera rejects automatic Wi-Fi activation, choose **Use manual Wi-Fi** and connect manually.

**Slow thumbnails** — The camera's Wi-Fi is 2.4GHz and not fast. Thumbnails load lazily; give it a few seconds.

## Architecture and validation

- `AppDelegate.swift` owns bootstrap, menus and the main AppKit window;
  `AppController.swift` owns modal/sheet presentation and platform lifecycle hooks.
- `PhotoSelection.swift` owns membership, active identity, range anchor and baseline.
- `BrowserModel.swift`, `NativeBrowser.swift`, and `NativeSettings.swift` provide
  observable presentation state and native views. Gallery identity uses directory
  plus filename, independently of image request completion.
- `Preferences.swift` retains the `settings.v1` record format;
  `CameraBluetooth.swift` retains `bluetooth-cameras.v1`. Bundle identity remains
  `local.GRBrowser`; this refactor requires no preference migration.
- `CameraConnection.swift` owns operation admission and verified sessions.
  `CameraDiscovery.swift` observes networks/devices without waking or joining;
  `SessionHealthMonitor.swift` reports health while the coordinator owns invalidation
  and history revisions. Platform and credential adapters live in `PlatformAccess.swift`.
- `CameraAPI.swift` centralizes encoded endpoints and User-Agent.
  `CameraHTTP.swift`, `CameraImageLoader.swift`, and `DownloadService.swift` retain
  separate verification, image, and original-transfer sessions. Downloads stage
  complete files, validate ZIPs, and publish without replacing existing outputs.
- `swift-build.py` is the shared source/framework/target/module-cache manifest for
  `make build`, `./build.sh`, and tests. Bundle staging, icons, signing and optional
  installation remain in `build.sh`.

Run all tests with:

```sh
python3 tests/run-tests.py
```

The runner compiles ordinary application sources with callable test suites and an
explicit `tests/main.swift` driver. Tests use local HTTP fixtures, isolated preferences,
fake radios/clocks, generated image fixtures, and real AppKit/SwiftUI hosts. They do
not connect or wake a physical camera. Focused native checks are available with
`GRBROWSER_TEST_SUITE=browser`, `settings`, or `images` before the same command.
The runner needs localhost socket and macOS UI access; sandboxed builds may also
need permission to launch the SwiftUI compiler macro plugin and `iconutil`.

Hardware results and unverified manual checks are recorded separately in the active
OpenSpec change's `validation.md`. Automated host/responder events do not establish
real OS input, VoiceOver navigation, production preference contents, or camera behavior.

## Credits

- Camera API reverse engineering: [Dima Kogan](https://notes.secretsauce.net/notes/2022/06/16_ricoh-gr-iiix-80211-reverse-engineering.html)
- Firmware exploration: [Hackaday project](https://hackaday.io/project/191721-ricoh-griiix-firmware-exploration-and-hacking)
- Bluetooth API specs: [dm-zharov/ricoh-gr-bluetooth-api](https://github.com/dm-zharov/ricoh-gr-bluetooth-api)

## License

MIT
