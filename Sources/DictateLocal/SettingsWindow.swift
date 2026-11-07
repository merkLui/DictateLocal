import Cocoa
import SwiftUI

class SettingsWindow: NSWindow {
    init(initialSection: SettingsSection = .general) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 470),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.title = "DictateLocal Settings"
        self.center()
        self.isReleasedWhenClosed = false

        // Liquid Glass / Apple System Settings style:
        // - titlebarAppearsTransparent makes the title bar area transparent
        // - titleVisibility = .hidden hides the title text
        // - fullSizeContentView (in styleMask above) allows content under title bar
        // - toolbarStyle = .unified collapses the toolbar to just the traffic light area
        //   and causes the sidebar to extend all the way to the top of the window
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .visible
        self.toolbarStyle = .unified

        // Attach an empty transparent toolbar so the sidebar can extend into the titlebar.
        let toolbar = NSToolbar(identifier: "SettingsWindowToolbar")
        self.toolbar = toolbar

        // The detail pane draws a standard material over the desktop, and the sidebar keeps its glass.
        self.isOpaque = false
        self.backgroundColor = .clear

        self.collectionBehavior = [.auxiliary, .managed, .fullScreenNone, .fullScreenDisallowsTiling]
        self.isMovableByWindowBackground = false

        let view = SettingsView(initialSection: initialSection)
        self.contentViewController = NSHostingController(rootView: view)
        self.setContentSize(NSSize(width: 680, height: 470))
    }

    /// Fits the window to the page, keeping its top edge in place, so no page ends in empty space.
    func fitHeight(_ height: CGFloat) {
        var newFrame = frameRect(forContentRect: NSRect(x: 0, y: 0, width: 680, height: height))
        newFrame.origin.x = frame.origin.x
        newFrame.origin.y = frame.maxY - newFrame.height
        guard newFrame != frame else { return }
        setFrame(newFrame, display: true, animate: isVisible)
    }
}
