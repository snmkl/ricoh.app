import Cocoa

func pickDownloadFolder(window: NSWindow?, initial: URL?, completion: @escaping (URL?) -> Void) {
    guard window?.attachedSheet == nil else { completion(nil); return }
    let panel = NSOpenPanel()
    panel.worksWhenModal = true
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
