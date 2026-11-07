import AppKit
import DictateCore
import SwiftUI

/// The menu bar icon, its menu and the settings window.
extension AppDelegate {
    func scheduleDictationClear() {
        dictationClearTimer?.invalidate()
        guard lastDictationText != nil else { return }
        // Clear RAM backup after 5 minutes (300 seconds)
        dictationClearTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
            self?.lastDictationText = nil
            perfLog("AX: Cleared ephemeral dictation RAM backup after 5 minutes timeout")
        }
    }

    func setupEditMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        applyStatusIcon(accessibilityDescription: "DictateLocal")

        let menu = NSMenu()
        statusItem.menu = menu
        updateMenuBarMenu()
    }

    func updateMenuBarMenu() {
        guard let menu = statusItem.menu else { return }

        menu.removeAllItems()

        if let status = modelStatusMenuTitle {
            let statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Custom SwiftUI-based Last Dictation menu item card (ephemeral, single-use RAM backup)
        if let text = lastDictationText, !text.isEmpty {
            let dictationItem = NSMenuItem()
            let hostingView = NSHostingView(rootView: LastDictationMenuItemView(text: text, onCopy: { [weak self] in
                guard let self = self else { return }

                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
                perfLog("AX: User copied last dictation manually from menu bar")

                NSSound(named: "Glass")?.play()
                self.lastDictationText = nil // Clear RAM backup so it instantly disappears!
                self.statusItem.menu?.cancelTracking()
            }))

            hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 26)
            dictationItem.view = hostingView
            menu.addItem(dictationItem)

            menu.addItem(NSMenuItem.separator())
        }

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings as () -> Void), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
    }

    var modelStatusMenuTitle: String? {
        switch ModelStatus.shared.state {
        case .preparing:                  return "Preparing speech model…"
        case .downloading(let percent):   return "Downloading speech model: \(percent) %"
        case .ready:                      return nil
        case .failed:                     return "Speech model download failed"
        }
    }

    func resetMenuBarIcon() {
        applyStatusIcon(accessibilityDescription: "DictateLocal")
    }

    @objc func openSettings() {
        openSettings(section: .general)
    }

    func openSettings(section: SettingsSection) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(initialSection: section)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applyStatusIcon(accessibilityDescription: String) {
        if let button = statusItem.button {
            button.image = Self.makeWaveBarStatusIcon(accessibilityDescription: accessibilityDescription)
            button.imagePosition = .imageOnly
            button.contentTintColor = nil
            button.alphaValue = 1
            button.isEnabled = true
        }
    }

    static func makeWaveBarStatusIcon(accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.black.setFill()

        let bars: [(x: CGFloat, height: CGFloat)] = [
            (1.2, 13.5),
            (4.9, 8.5),
            (8.6, 15.5),
            (12.3, 8.5),
            (16.0, 13.5)
        ]

        for bar in bars {
            let width: CGFloat = 2.2
            let rect = NSRect(
                x: bar.x,
                y: (18 - bar.height) / 2,
                width: width,
                height: bar.height
            )
            NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
