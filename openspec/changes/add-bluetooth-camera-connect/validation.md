## Software validation

Validated on macOS 26.6.2 / Apple Silicon, targeting macOS 13.3.

- The signed `python3 tests/run-tests.py` harness passes the existing download, output-integrity, collision, settings, credential, reconnect and native-modal regressions plus the Bluetooth checks below. It uses a loopback HTTP fixture and injected Bluetooth/Wi-Fi control; it does not pair or control a physical camera.
- BLE protocol tests exercise strict UTF-8/NUL handling, credential validation, identity-before-write ordering, exact one-byte writes, conditional power/AP activation, already-prepared cameras, unsupported identities/states, application rejection without retry loops, an AP-transition disconnect with cached credentials, timeouts and obsolete responses after cancellation.
- The paired-device label refinement passes the full signed regression suite. Injected name tests verify exact UTF-8 Computer Name bytes (including Unicode), protected checks before naming, refresh after a Mac rename, skipped missing/blank/embedded-NUL names, best-effort handling of unsupported/rejected labels, and no power/WLAN activation after link loss during naming. The optional naming characteristic does not change required camera services. Both build paths link SystemConfiguration for the native Computer Name API.
- Coordinator tests exercise prerequisite denial before BLE setup, ephemeral credential priority without Keychain access/persistence, one credential refresh, model mismatch, empty-library success, BLE release with a live Wi-Fi session, cancellation while BLE drains, cancellation during a blocking association, cancellation before a queued association starts, and sleep invalidation.
- Device-history tests cover explicit selection without wake, independent persistence, presence expiry, system-connected versus app-connected state, protection of an active remembered camera, network unlinking and independent camera removal. Existing tests cover network Forget revisions and late callbacks.
- The actual WebKit/native bridge runs a fake-camera handoff through CONNECT, displays the safe device name and Released state, changes the primary action to DISCONNECT, cancels through the CANCELLING drain state, and offers an explicit manual route after rejection without starting another connection. Minimum-width geometry and the connection live region are checked. The rendered interface is captured at `build/bluetooth-ui.png` for visual review.
- The actual HTTP identity verifier is exercised against `/v1/props`, accepting the expected model/serial and rejecting another model.
- `make build` and `./build.sh` pass. The latter produces `build/GRBrowser.app`; its manifest contains the Bluetooth usage description and `codesign --verify --strict` succeeds. The sandboxed icon-packaging invocation failed with Invalid Iconset; the unchanged packaging step succeeded when the build ran outside the sandbox.
- The regression fixture requires loopback server permission and runs outside the filesystem/network sandbox. All Bluetooth adapters in the harness are fakes. The existing optional native Wi-Fi probe reported its permission fallback; no network association was performed by that probe.
- `openspec validate --all --strict --no-interactive` and `git diff --check` pass. The completed settings/Wi-Fi baseline was archived and its canonical specs installed before implementation.

## Physical validation

On 2026-10-21, the user reported testing Bluetooth successfully. This confirms a working user-tested Bluetooth path; the camera firmware, macOS version, starting power state and stage timings were not supplied. It does not establish every hardware acceptance case below.

The subsequent compact-header UI refinement passes the full signed regression suite and bundle build. The real WebKit check verifies a single header line at 480 pixels, Find cameras immediately after the selector, no duplicate Wi-Fi status row, Bluetooth/Wi-Fi icon changes, safely rendered camera names and distinct choices for duplicate names. The refreshed `build/bluetooth-ui.png` was visually inspected.

Tasks 1.2, 1.3 and 1.4 remain unchecked until their detailed acceptance evidence is recorded. The agent's automated checks used injected radios; the user's successful Bluetooth test is recorded separately above.

Required evidence: intended GR IIIx model/firmware and macOS pairing behavior; protected reads across app relaunch; Computer Name displayed in the camera's paired-device list and refreshed after renaming the Mac; on/sleep/off wake behavior with On anytime; actual AP activation, association and complete photo download; measured timings; and AP/batch stability after releasing BLE. External GitHub reports and passing fake-radio tests do not establish those results for this app.

The Bluetooth setup UI continues to label the feature experimental. The README now focuses on setup and everyday use. Current Wi-Fi/manual activation remains available. Manual VoiceOver operation and real macOS Bluetooth permission/passkey prompts have not been exercised by the automated checks.

### BLE release timing acceptance

The current app releases BLE immediately after Wi-Fi association, stable SSID and camera HTTP identity/library verification succeed. It waits for the BLE disconnect to drain before publishing the ready library. There is no added grace period. The selector's **Released** state with loaded photos is the visible starting point for post-release checks.

- Start a large real-file batch immediately after **Released** appears. Verify that every download completes and the saved files open.
- On a separate connection, leave the library idle for five minutes after **Released**, then load a fresh preview and download a previously unopened photo. Confirm that camera Wi-Fi stays connected and the app does not need a new Bluetooth connection. Record the camera's configured auto-power-off interval; an intentional camera shutdown must be distinguished from AP loss caused by BLE release.
- Repeat from camera on, asleep and off with **On anytime**, at least three times per starting state, including after quitting/reopening the app. Record CONNECT-to-library time, any visible Finishing duration, and elapsed time from Released to any Wi-Fi/HTTP loss.
- Record camera model/firmware, macOS version, starting state, auto-power-off setting, batch size/duration and result. A repeatable Wi-Fi loss immediately after release requires investigating BLE retention or a measured grace period before changing the policy.
