import Cocoa

@MainActor func runChecks() {
    switch ProcessInfo.processInfo.environment["GRBROWSER_TEST_SUITE"] {
    case "settings": runSettingsTests()
    case "images": runImageLoaderTests()
    case "selection": runSelectionTests(); runNativeSelectionTests()
    case "browser": runSelectionTests(); runNativeSelectionTests(); runNativeBrowserTests(); runNativeAdmissionTests()
    default:
        runSelectionTests()
        runNativeSelectionTests()
        runNativeBrowserTests()
        runNativeAdmissionTests()
        runImageLoaderTests()
        runDownloadTests()
        runCameraAPITests()
        runPreferenceTests()
        runConnectionTests()
        runSettingsTests()
        runBluetoothProtocolTests()
        runBluetoothTests()
    }
    for domain in preferenceDomains { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
}

// Run checks from a real AppKit event loop, matching the production host lifecycle.
MainActor.assumeIsolated { _ = app.setActivationPolicy(.regular) }
RunLoop.main.perform {
    MainActor.assumeIsolated {
        runChecks()
        fflush(stdout)
        exit(0)
    }
}
MainActor.assumeIsolated { app.run() }
