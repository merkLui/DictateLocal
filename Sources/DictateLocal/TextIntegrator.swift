import Cocoa
import ApplicationServices
import Carbon
import DictateCore

enum TextIntegrationResult {
    case pasteAttempted
    case failed
}

final class TextIntegrator {
    private var initialAppPID: pid_t = 0
    private var initialApp: NSRunningApplication?

    var targetAppPID: pid_t { initialAppPID }

    private(set) var accumulatedText = ""
    private var activeProvider: LazyTextProvider?

    // Live typing state. Only touched on the main thread.
    private(set) var isTypingLive = false
    private(set) var lostLiveTarget = false
    private(set) var targetIsSecure = false
    private(set) var targetIsSingleLine = false
    private var liveTyped = ""
    private var focusedTarget: AXUIElement?
    private var captureGeneration = 0
    private var waitsForTarget = false
    private let typingQueue = DispatchQueue(label: "DictateLocal.typing", qos: .userInteractive)
    private var clipboardToRestore: [NSPasteboardItem]?
    private var latestPasteChangeCount = 0

    func captureActiveApp(typesLive: Bool) {
        initialApp = NSWorkspace.shared.frontmostApplication
        initialAppPID = initialApp?.processIdentifier ?? 0
        accumulatedText = ""
        isTypingLive = false
        lostLiveTarget = false
        targetIsSecure = false
        targetIsSingleLine = false
        liveTyped = ""
        focusedTarget = nil
        captureGeneration += 1
        waitsForTarget = typesLive

        guard let app = initialApp else { return }
        readTarget(of: app, typesLive: typesLive, generation: captureGeneration, retriesLeft: nil)
    }

    /// A woken browser takes about two seconds to expose its fields. Typing then starts with the
    /// text so far, so nothing is lost. `retriesLeft` is nil on the first read.
    private func readTarget(of app: NSRunningApplication, typesLive: Bool, generation: Int, retriesLeft: Int?) {
        // Reading the focused element can block on the target app, so it stays off the main thread.
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self, AXIsProcessTrusted() else { return }
            let available = retriesLeft ?? (self.wakeAccessibilityTreeIfNeeded(for: app) ? 30 : 0)
            let element = self.copyFocusedElement(in: app)
            let secure = IsSecureEventInputEnabled() || element.map(self.isSecureField) ?? false
            let editable = element.map(self.isEditable) ?? false
            let singleLine = element.map(self.isSingleLine) ?? false
            let retries = editable || secure || !typesLive ? 0 : available
            if retries == 0 {
                let role = element.flatMap { self.role(of: $0) } ?? "none"
                perfLog("AX: Live typing target app=\(app.bundleIdentifier ?? "unknown") role=\(role) editable=\(editable) secure=\(secure)")
            }
            DispatchQueue.main.async {
                guard self.captureGeneration == generation else { return }
                // The target app may hang; dictation must not hang with it.
                if let element { AXUIElementSetMessagingTimeout(element, 0.2) }
                self.focusedTarget = element
                self.targetIsSecure = secure
                self.targetIsSingleLine = singleLine
                self.isTypingLive = typesLive && editable && !secure
                guard retries > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard self.captureGeneration == generation, self.waitsForTarget,
                          NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                    self.readTarget(of: app, typesLive: typesLive, generation: generation, retriesLeft: retries - 1)
                }
            }
        }
    }

    /// Dictation is over, so a field that appears from now on no longer gets live text.
    func stopWaitingForTarget() {
        waitsForTarget = false
    }

    // MARK: - Live Typing

    /// Brings the text at the cursor in line with the target. Typing stops as soon as the target can
    /// no longer be trusted, so keystrokes never land somewhere else and never delete foreign text.
    func updateLiveText(_ target: String) {
        guard isTypingLive else { return }

        let edit = LiveText.edit(from: liveTyped, to: target)
        guard edit.deleteCount > 0 || !edit.insert.isEmpty else { return }
        guard isTargetStillFocused(strict: edit.deleteCount > 0),
              edit.deleteCount == 0 || textBeforeCursorEnds(with: String(liveTyped.suffix(edit.deleteCount))) else {
            stopLiveTyping()
            return
        }

        liveTyped = target
        let app = initialApp
        let element = focusedTarget
        typingQueue.async { [weak self] in
            guard let self else { return }
            // Events may wait in this queue and take a while, so the target is checked again while posting.
            let isTarget = { self.isFocused(element, in: app, strict: edit.deleteCount > 0) }
            guard self.postBackspaces(edit.deleteCount, while: isTarget),
                  self.postText(edit.insert, while: isTarget) else {
                DispatchQueue.main.async { self.stopLiveTyping() }
                return
            }
        }
    }

    /// Replaces the typed text from its first difference on, pasting what follows.
    /// The paste only happens once the deletion shows in the same field.
    func finishLiveTextByPasting(_ target: String, onSuccess: @escaping () -> Void, onFailure: @escaping () -> Void) {
        let edit = LiveText.edit(from: liveTyped, to: target)
        updateLiveText(String(target.dropLast(edit.insert.count)))
        guard isTypingLive else {
            onFailure()
            return
        }
        let generation = captureGeneration
        accumulatedText = edit.insert
        whenTypingFinished { [weak self] in
            self?.pasteWhenCutIsVisible(generation: generation, retries: 6, onSuccess: onSuccess, onFailure: onFailure)
        }
    }

    private func pasteWhenCutIsVisible(generation: Int, retries: Int, onSuccess: @escaping () -> Void, onFailure: @escaping () -> Void) {
        guard captureGeneration == generation else { return }
        guard isTypingLive else {
            onFailure()
            return
        }
        guard cutIsVisible else {
            guard retries > 0 else {
                stopLiveTyping()
                onFailure()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.pasteWhenCutIsVisible(generation: generation, retries: retries - 1, onSuccess: onSuccess, onFailure: onFailure)
            }
            return
        }
        pasteViaTransientClipboard(canPaste: { [weak self] in
            guard let self else { return false }
            return self.captureGeneration == generation && self.cutIsVisible
        }, onSuccess: onSuccess, onFailure: onFailure)
    }

    private var cutIsVisible: Bool {
        isTargetStillFocused(strict: true) && textBeforeCursorEnds(with: liveTyped)
    }

    /// Reports whether the typed text can become `target` without deleting anything unverified.
    /// The target app may still be working through the last keystrokes, so this checks a few times.
    func whenRewritable(to target: String, retries: Int = 6, _ completion: @escaping (Bool) -> Void) {
        whenTypingFinished { [weak self] in
            guard let self else { return }
            guard !self.canRewriteLiveText(to: target) else {
                completion(true)
                return
            }
            guard retries > 0 else {
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.whenRewritable(to: target, retries: retries - 1, completion)
            }
        }
    }

    private func canRewriteLiveText(to target: String) -> Bool {
        guard isTypingLive else { return false }
        let deleteCount = LiveText.edit(from: liveTyped, to: target).deleteCount
        return deleteCount == 0 || (isTargetStillFocused(strict: true)
            && textBeforeCursorEnds(with: String(liveTyped.suffix(deleteCount))))
    }

    private func stopLiveTyping() {
        isTypingLive = false
        lostLiveTarget = true
        perfLog("AX: Target changed; stopped live typing")
    }

    private func isTargetStillFocused(strict: Bool) -> Bool {
        isFocused(focusedTarget, in: initialApp, strict: strict)
    }

    /// `strict` also requires a readable match, because deleting at the wrong place loses user text.
    private func isFocused(_ target: AXUIElement?, in app: NSRunningApplication?, strict: Bool) -> Bool {
        guard let app, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              !IsSecureEventInputEnabled() else { return false }
        guard let current = copyFocusedElement(in: app) else { return !strict }
        guard !isSecureField(current) else { return false }
        guard let target else { return !strict }
        return CFEqual(current, target)
    }

    /// Fields that do not expose their text cannot be verified and count as a mismatch.
    private func textBeforeCursorEnds(with expected: String) -> Bool {
        guard let element = focusedTarget else { return false }
        var valueRef: CFTypeRef?
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let value = valueRef as? String,
              AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeValue = rangeRef, CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return false
        }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length == 0 else { return false }
        return (value as NSString).substring(to: min(range.location, (value as NSString).length)).hasSuffix(expected)
    }

    /// Runs once everything queued has been typed.
    func whenTypingFinished(_ action: @escaping () -> Void) {
        typingQueue.async {
            DispatchQueue.main.async(execute: action)
        }
    }

    /// Removes what was typed for a dictation the user discarded.
    func discardLiveText() {
        waitsForTarget = false
        if isTypingLive { updateLiveText("") }
        isTypingLive = false
    }

    /// False once `isTarget` fails, which it is asked before the first event and again every few.
    private func postText(_ text: String, while isTarget: () -> Bool) -> Bool {
        guard !text.isEmpty else { return true }
        guard isTarget() else { return false }
        let src = CGEventSource(stateID: .privateState)
        var chunk = ""
        var posted = 0
        // A single keyboard event carries a limited number of characters.
        func flush() {
            guard !chunk.isEmpty, !IsSecureEventInputEnabled() else { return }
            let units = Array(chunk.utf16)
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: isDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
            chunk = ""
            usleep(1_000)
        }
        for character in text {
            if chunk.utf16.count + character.utf16.count > 16 {
                flush()
                posted += 1
                if posted % 4 == 0, !isTarget() { return false }
            }
            chunk.append(character)
        }
        flush()
        return true
    }

    private func postBackspaces(_ count: Int, while isTarget: () -> Bool) -> Bool {
        let src = CGEventSource(stateID: .privateState)
        for index in 0..<count {
            if index % 32 == 0, !isTarget() { return false }
            for isDown in [true, false] {
                // virtualKey 51 is Delete.
                guard let event = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: isDown) else { continue }
                event.flags = []
                event.post(tap: .cghidEventTap)
            }
            usleep(1_000)
        }
        return true
    }

    private func copyFocusedElement(in app: NSRunningApplication) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        // The target app may hang; dictation must not hang with it.
        AXUIElementSetMessagingTimeout(systemWide, 0.2)
        return copyAXElement(from: systemWide, attribute: kAXFocusedUIElementAttribute as CFString)
            ?? copyAXElement(from: AXUIElementCreateApplication(app.processIdentifier), attribute: kAXFocusedUIElementAttribute as CFString)
    }

    private func isSecureField(_ element: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &valueRef) == .success else { return false }
        return valueRef as? String == kAXSecureTextFieldSubrole as String
    }

    private func role(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &valueRef) == .success else { return nil }
        return valueRef as? String
    }

    private func isSingleLine(_ element: AXUIElement) -> Bool {
        guard let role = role(of: element) else { return false }
        return role == kAXTextFieldRole as String || role == kAXComboBoxRole as String
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        var valueRef: CFTypeRef?
        let hasRole = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &valueRef) == .success
        let role = hasRole ? valueRef as? String ?? "" : ""
        let textRoles = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXWebArea", // HTML web pages in Safari, Chrome, Atlas, etc.
            "AXGroup"    // Rich text and custom input boxes (Slack, Notion, Mistral AI)
        ]
        if textRoles.contains(role) { return true }

        valueRef = nil
        let hasEditable = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &valueRef) == .success
        return hasEditable && valueRef as? Bool == true
    }

    private func copyAXElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard result == .success, let value = valueRef, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    /// Returns whether the app is built on Chromium, whose fields may only appear a moment later.
    private func wakeAccessibilityTreeIfNeeded(for app: NSRunningApplication) -> Bool {
        let bundleID = (app.bundleIdentifier ?? "").lowercased()
        let appName = (app.localizedName ?? "").lowercased()
        let chromiumSignals = ["chrome", "chromium", "electron", "code", "slack", "cursor", "obsidian", "discord", "notion", "arc", "antigravity"]
        let isChromium = isBuiltOnChromium(app)
        guard isChromium || chromiumSignals.contains(where: { bundleID.contains($0) || appName.contains($0) }) else {
            return false
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        let manual = AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        // Electron understands the attribute above. Browsers such as Helium only react to this one.
        if manual != .success, isChromium {
            _ = AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        usleep(50_000)
        return isChromium
    }

    /// Chromium apps ship "<Name> Framework.framework", whatever the browser is called.
    private func isBuiltOnChromium(_ app: NSRunningApplication) -> Bool {
        guard let frameworks = app.bundleURL?.appendingPathComponent("Contents/Frameworks").path,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: frameworks) else { return false }
        return contents.contains { $0.hasSuffix(" Framework.framework") }
    }

    // MARK: - Paste

    func setText(_ text: String) {
        accumulatedText = text
    }

    func finalizeIntegration(onSuccess: @escaping () -> Void, onFailure: @escaping () -> Void) -> TextIntegrationResult {
        guard !accumulatedText.isEmpty else { return .failed }

        pasteViaTransientClipboard(canPaste: { true }, onSuccess: onSuccess, onFailure: onFailure)
        return .pasteAttempted
    }

    @discardableResult
    private func activateInitialTargetApp() -> Bool {
        guard initialAppPID > 0 else { return false }

        let script = """
        ObjC.import("AppKit");
        const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(\(initialAppPID));
        if (app.isNil()) {
          "not_found";
        } else {
          app.activateWithOptions(2);
          "ok";
        }
        """

        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-l", "JavaScript", "-e", script]
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ok = task.terminationStatus == 0 && result == "ok"
            perfLog("AX: Activated target pid \(initialAppPID) via AppKit script ok=\(ok)")
            return ok
        } catch {
            let fallbackOK = initialApp?.activate(options: []) ?? false
            perfLog("AX: Target pid activation script failed: \(error.localizedDescription). fallbackOK=\(fallbackOK)")
            return fallbackOK
        }
    }

    private func pasteViaTransientClipboard(canPaste: @escaping () -> Bool, onSuccess: @escaping () -> Void, onFailure: @escaping () -> Void) {
        let pasteboard = NSPasteboard.general
        // A paste still waiting to restore the clipboard holds what belongs to the user.
        let previousItems = clipboardToRestore ?? deepCopy(items: pasteboard.pasteboardItems ?? [])
        clipboardToRestore = previousItems
        let item = NSPasteboardItem()

        // Use our lazy provider to detect if the text is actually read (pasted)
        let provider = LazyTextProvider(text: accumulatedText) {
            DispatchQueue.main.async {
                perfLog("AX: Lazy pasteboard data provider callback triggered! Paste successful.")
                onSuccess()
            }
        }
        self.activeProvider = provider

        item.setDataProvider(provider, forTypes: [.string])
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("de.petermaurer.TransientPasteboardType"))

        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let ownChangeCount = pasteboard.changeCount
        latestPasteChangeCount = ownChangeCount
        activateInitialTargetApp()

        // Post paste keystroke after a slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard !IsSecureEventInputEnabled(), canPaste() else { return }
            self.postPasteKeystroke()
        }

        // Check if the data was requested within 350ms. If not, trigger failure (focus lost)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }
            if self.activeProvider === provider && !provider.wasRead {
                perfLog("AX: Lazy pasteboard was never read within 350ms. Assuming paste failed.")
                onFailure()
            }
            if self.activeProvider === provider {
                self.activeProvider = nil
            }
        }

        // Restore original clipboard contents after 450ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            // A later paste restores instead.
            guard self.latestPasteChangeCount == ownChangeCount else { return }
            self.clipboardToRestore = nil
            // Anything copied in the meantime belongs to the user and stays.
            guard pasteboard.changeCount == ownChangeCount else { return }
            pasteboard.clearContents()
            if !previousItems.isEmpty {
                pasteboard.writeObjects(previousItems)
            }
        }

        perfLog("AX: Pasting via lazy transient clipboard into pid \(initialAppPID)")
    }

    private func postPasteKeystroke() {
        let src = CGEventSource(stateID: .privateState)

        // virtualKey 9 corresponds to 'V' key on US and German QWERTZ keyboards
        guard let cmdVDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let cmdVUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else {
            perfLog("AX: Failed to create robust Cmd+V events")
            return
        }

        cmdVDown.flags = .maskCommand
        cmdVUp.flags = .maskCommand

        // Post events globally to the system session (highly robust across all apps)
        cmdVDown.post(tap: .cghidEventTap)
        cmdVUp.post(tap: .cghidEventTap)

        perfLog("AX: Posted robust global Cmd+V keystroke")
    }

    private func deepCopy(items: [NSPasteboardItem]) -> [NSPasteboardItem] {
        return items.map { item in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
    }
}

// MARK: - Lazy Text Pasteboard Provider

final class LazyTextProvider: NSObject, NSPasteboardItemDataProvider {
    let text: String
    private(set) var wasRead = false
    private let onRead: () -> Void

    init(text: String, onRead: @escaping () -> Void) {
        self.text = text
        self.onRead = onRead
        super.init()
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .string {
            wasRead = true
            item.setString(text, forType: .string)
            onRead()
        }
    }
}
