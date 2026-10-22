#!/usr/bin/env python3
"""Compile the real app code into a harness and exercise it against a local camera fixture."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import platform
import socket
import shutil
import subprocess
import tempfile
import threading
import time
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
PAYLOAD = bytes(range(256)) * 8192


class CameraFixture(BaseHTTPRequestHandler):
    def do_GET(self):
        path = unquote(self.path)
        if path == '/v1/props':
            data = json.dumps({'model': 'RICOH GR IIIx', 'serialNo': 'fixture-serial'}).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path in ['/v1/ping', '/v1/photos']:
            data = b'{}' if path.endswith('/ping') else json.dumps({'dirs': []}).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path.endswith('/missing.JPG'):
            self.send_error(404, 'Photo not found')
            return
        self.send_response(200)
        self.send_header('Content-Type', 'image/jpeg')
        if not path.endswith('/unknown.JPG'):
            self.send_header('Content-Length', str(len(PAYLOAD)))
        self.end_headers()
        try:
            limit = len(PAYLOAD) // 4 if path.endswith('/interrupted.JPG') else len(PAYLOAD)
            for offset in range(0, limit, 65536):
                self.wfile.write(PAYLOAD[offset:offset + 65536])
                self.wfile.flush()
                time.sleep(0.025)
            if path.endswith('/interrupted.JPG'):
                self.connection.shutdown(socket.SHUT_RDWR)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def log_message(self, *args):
        pass


(ROOT / 'build').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='download-tests-', dir=ROOT / 'build') as directory:
    work = Path(directory)
    source = (ROOT / 'GRBrowser.swift').read_text().split('// MARK: - App Delegate')[0]
    main = work / 'main.swift'
    main.write_text(source + '\n' + (ROOT / 'tests/DownloadTests.swift').read_text() + '\n' + (ROOT / 'tests/SettingsTests.swift').read_text() + '\n' + (ROOT / 'tests/BluetoothTests.swift').read_text())
    bundle = work / 'GRBrowserChecks.app'
    contents = bundle / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    shutil.copy2(ROOT / 'Info.plist', contents / 'Info.plist')
    binary = contents / 'MacOS' / 'GRBrowser'
    subprocess.run([
        'xcrun', 'swiftc', str(main), str(ROOT / 'CameraBluetooth.swift'),
        str(ROOT / 'CoreBluetoothTransport.swift'), str(ROOT / 'BluetoothConnection.swift'), '-o', str(binary),
        '-module-cache-path', str(ROOT / 'build/ModuleCache'),
        '-target', f'{platform.machine()}-apple-macosx13.3',
        '-framework', 'SystemConfiguration', '-framework', 'CoreBluetooth', '-framework', 'CoreWLAN', '-framework', 'CoreLocation', '-framework', 'Security',
        '-framework', 'Cocoa', '-framework', 'WebKit', '-framework', 'UniformTypeIdentifiers',
    ], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(bundle)], check=True)
    server = ThreadingHTTPServer(('127.0.0.1', 0), CameraFixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        subprocess.run([str(binary), f'http://127.0.0.1:{server.server_port}', str(work)],
                       check=True, timeout=180)
    finally:
        server.shutdown()
