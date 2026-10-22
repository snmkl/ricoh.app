# GR IIIx Browser

A native macOS app to browse and download photos from your Ricoh GR IIIx over Wi-Fi. No phone app needed.

## How it works

The GR IIIx runs a small HTTP server on `192.168.0.1:80` when Wi-Fi is enabled. The official Ricoh GR app is just a client for this API. This app does the same thing, but on your laptop.

A `WKWebView` renders the UI. A custom URL scheme handler (`gr-cam://`) intercepts API calls and forwards them to the camera via `URLSession` — no proxy server, no CORS issues, no dependencies.

## Requirements

- macOS 13.3 or later (Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`) for building

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
4. Browse thumbnails, click to preview, select multiple, download as zip

### Connect via Bluetooth

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

**Empty grid** — The `/v1/photos` response shape may vary across firmware versions. Open Safari Web Inspector (Develop → GRBrowser) and check the console for the raw JSON. Open an issue with the output.

**Camera not found over Bluetooth** — Check that camera Bluetooth is enabled, move it closer, and disconnect any phone app using it. Use **On anytime** for connection while the camera is off.

**Pairing or automatic connection failed** — Follow the camera's pairing instructions and complete the macOS passkey prompt. Check Mac Bluetooth, Wi-Fi and Location Services permissions. If the camera rejects automatic Wi-Fi activation, choose **Use camera Wi-Fi** and connect manually.

**Slow thumbnails** — The camera's Wi-Fi is 2.4GHz and not fast. Thumbnails load lazily; give it a few seconds.

## Credits

- Camera API reverse engineering: [Dima Kogan](https://notes.secretsauce.net/notes/2022/06/16_ricoh-gr-iiix-80211-reverse-engineering.html)
- Firmware exploration: [Hackaday project](https://hackaday.io/project/191721-ricoh-griiix-firmware-exploration-and-hacking)
- Bluetooth API specs: [dm-zharov/ricoh-gr-bluetooth-api](https://github.com/dm-zharov/ricoh-gr-bluetooth-api)

## License

MIT
# ricoh.app
