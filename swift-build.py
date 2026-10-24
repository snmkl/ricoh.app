#!/usr/bin/env python3
"""Shared compiler/source manifest for binary, bundle, and fixture builds."""
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
SOURCES = [
    'CameraImageLoader.swift', 'CameraAPI.swift', 'OperationModels.swift', 'Preferences.swift', 'PlatformAccess.swift', 'CameraHTTP.swift',
    'CameraDiscovery.swift', 'SessionHealthMonitor.swift', 'CameraConnection.swift', 'DownloadService.swift', 'FolderChooser.swift',
    'CameraBluetooth.swift', 'CoreBluetoothTransport.swift', 'BluetoothConnection.swift',
    'PhotoSelection.swift', 'NativeBrowser.swift', 'NativeSettings.swift', 'BrowserModel.swift', 'AppController.swift', 'AppDelegate.swift',
]
FRAMEWORKS = ['CoreBluetooth', 'CoreWLAN', 'CoreLocation',
              'Security', 'Cocoa', 'SwiftUI', 'ImageIO']

def compile_swift(output, *, tests=False, embedded_plist=False):
    sources = [ROOT / s for s in SOURCES]
    sources += sorted((ROOT / 'tests').glob('*.swift')) if tests else [ROOT / 'main.swift']
    command = ['xcrun', 'swiftc', *map(str, sources), '-o', str(output),
               '-module-cache-path', str(ROOT / 'build/ModuleCache'),
               '-target', f'{platform.machine()}-apple-macosx13.3']
    for framework in FRAMEWORKS:
        command += ['-framework', framework]
    if embedded_plist:
        command += ['-Xlinker', '-sectcreate', '-Xlinker', '__TEXT',
                    '-Xlinker', '__info_plist', '-Xlinker', str(ROOT / 'Info.plist')]
    if not tests:
        command += ['-O']
    subprocess.run(command, check=True)

if __name__ == '__main__':
    compile_swift(sys.argv[1], embedded_plist='--embedded-plist' in sys.argv[2:])
