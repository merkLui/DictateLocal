import Cocoa
import SwiftUI

class HUDWindow: NSPanel {
    /// Transparent room around the capsule so its glass rim isn't clipped at the window edge.
    static let edgeInset: CGFloat = 6

    private var hostingView: NSHostingView<HUDView>?
    private var hudViewState = HUDViewState()
    private weak var appDelegate: AppDelegate?
    
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        
        super.init(
            contentRect: NSRect(origin: .zero, size: HUDWindow.paddedSize(width: 230, height: 40)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .statusBar
        self.backgroundColor = .clear
        self.isOpaque = false
        // The window shadow is traced from the alpha mask and draws a jagged outline; the glass has its own.
        self.hasShadow = false
        self.ignoresMouseEvents = false // Enable clicking X / ✓ buttons
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        // Setup SwiftUI View
        let view = HUDView(state: hudViewState, appDelegate: appDelegate)
        self.hostingView = NSHostingView(rootView: view)
        self.contentView = hostingView
        
        // Hide by default
        self.orderOut(nil)
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        performDrag(with: event)
    }
    
    func showHUD(mode: RecordMode) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Set view state
            self.hudViewState.displayMode = mode == .pushToTalk ? .recordingHold : .recordingToggle
            self.hudViewState.textPreview = ""
            self.hudViewState.resetLevels()
            
            // Adjust frame size: 15-20% smaller heights and widths for sleeker look
            let width: CGFloat = mode == .pushToTalk ? 130 : 230
            let height: CGFloat = 40
            self.setFrame(NSRect(origin: .zero, size: HUDWindow.paddedSize(width: width, height: height)), display: true)
            
            // Center HUD horizontally near the bottom of the screen
            self.centerOnBottomScreen()
            
            // Fade in window
            self.alphaValue = 0.0
            self.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.animator().alphaValue = 1.0
            }, completionHandler: nil)
            
            // Start updating micro waveform volume meter
            self.startVolumePolling()
        }
    }
    
    func showProcessing() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.hudViewState.displayMode = .processing
            
            // Collapse size for processing (three dots) - 15-20% smaller
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                let currentFrame = self.frame
                let newSize = HUDWindow.paddedSize(width: 90, height: 40)
                let newX = currentFrame.origin.x + (currentFrame.width - newSize.width) / 2
                self.animator().setFrame(NSRect(origin: NSPoint(x: newX, y: currentFrame.origin.y), size: newSize), display: true)
            }, completionHandler: nil)
        }
    }
    
    func showClipboardCapsule(text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.hudViewState.textPreview = text
            self.hudViewState.displayMode = .clipboard
            
            // Expand size for clipboard capsule (larger text preview and copy button) - 15-20% smaller
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                let currentFrame = self.frame
                let newSize = HUDWindow.paddedSize(width: 320, height: 56)
                let newX = currentFrame.origin.x + (currentFrame.width - newSize.width) / 2
                self.animator().setFrame(NSRect(origin: NSPoint(x: newX, y: currentFrame.origin.y), size: newSize), display: true)
            }, completionHandler: nil)
        }
    }

    func showErrorToast(title: String, message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.hudViewState.errorTitle = title
            self.hudViewState.errorMessage = ""
            self.hudViewState.displayMode = .error

            // Measure the exact text width using NSFont to make it auto-sizing
            let font = NSFont.systemFont(ofSize: 10, weight: .bold)
            let titleSize = (title as NSString).size(withAttributes: [.font: font])
            let width = max(130, titleSize.width + 60) // exact text width + icon + spacing + padding + margin
            let height: CGFloat = 38

            // Animate frame transition smoothly to the measured width
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                let currentFrame = self.frame
                let newSize = HUDWindow.paddedSize(width: width, height: height)
                let newX = currentFrame.origin.x + (currentFrame.width - newSize.width) / 2
                let newY = currentFrame.origin.y + (currentFrame.height - newSize.height) / 2
                self.animator().setFrame(NSRect(origin: NSPoint(x: newX, y: newY), size: newSize), display: true)
            }, completionHandler: nil)

            self.alphaValue = 0.0
            self.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.animator().alphaValue = 1.0
            }, completionHandler: nil)

            // Auto-dismiss after 2.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self = self, self.hudViewState.displayMode == .error else { return }
                self.hideHUD()
            }
        }
    }

    func hideHUD() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                self.animator().alphaValue = 0.0
            }, completionHandler: {
                self.orderOut(nil)
                self.hudViewState.displayMode = .recordingHold
            })
        }
    }
    
    private static func paddedSize(width: CGFloat, height: CGFloat) -> NSSize {
        NSSize(width: width + edgeInset * 2, height: height + edgeInset * 2)
    }

    private func centerOnBottomScreen() {
        if let screen = NSScreen.main {
            let screenVisibleFrame = screen.visibleFrame
            let x = screenVisibleFrame.origin.x + (screenVisibleFrame.width - self.frame.width) / 2
            // Float 10% above the bottom screen safety area
            let y = screenVisibleFrame.origin.y + (screenVisibleFrame.height * 0.10)
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    // MARK: - Metering Polling
    
    private var timer: Timer?
    
    private func startVolumePolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let delegate = self.appDelegate, delegate.isRecording {
                let level = delegate.recorderManager.getAudioLevel()
                DispatchQueue.main.async {
                    self.hudViewState.pushLevel(level)
                }
            } else {
                self.timer?.invalidate()
            }
        }
    }

}
