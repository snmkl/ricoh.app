# GR IIIx Browser

A native macOS app to browse and download photos from your Ricoh GR IIIx over Wi-Fi. No phone app needed.

## How it works

The GR IIIx runs a small HTTP server on `192.168.0.1:80` when Wi-Fi is enabled. The official Ricoh GR app is just a client for this API. This app does the same thing, but on your laptop.

A `WKWebView` renders the UI. A custom URL scheme handler (`gr-cam://`) intercepts API calls and forwards them to the camera via `URLSession` — no proxy server, no CORS issues, no dependencies.

## Requirements

- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`)

## Build & Run

```
make run
```

That's it. Binary lands in `build/GRBrowser`.

## Usage

1. Turn on Wi-Fi on your GR IIIx (Menu → Wireless → Wi-Fi)
2. Connect your Mac to the camera's network (SSID shown on camera screen)
3. Open the app and hit **CONNECT**
4. Browse thumbnails, click to preview, select multiple, download as zip

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

**Slow thumbnails** — The camera's Wi-Fi is 2.4GHz and not fast. Thumbnails load lazily; give it a few seconds.

## Credits

- Camera API reverse engineering: [Dima Kogan](https://notes.secretsauce.net/notes/2022/06/16_ricoh-gr-iiix-80211-reverse-engineering.html)
- Firmware exploration: [Hackaday project](https://hackaday.io/project/191721-ricoh-griiix-firmware-exploration-and-hacking)
- Bluetooth API specs: [dm-zharov/ricoh-gr-bluetooth-api](https://github.com/dm-zharov/ricoh-gr-bluetooth-api)

## License

MIT
# ricoh.app
