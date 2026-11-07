import Cocoa

// Entrypoint for the standalone macOS app without main storyboard
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
