import AppKit
import DictateCore

/// One dictation from shortcut press to inserted text.
extension AppDelegate {
    func startRecordingFlow() {
        guard !isRecording else { return }

        isRecording = true
        currentRecordMode = .pushToTalk // Defaults to Hold, HotkeyManager updates this if it's a Tap

        // Show Floating HUD (waveform state) immediately on the main thread
        hudWindow?.showHUD(mode: currentRecordMode)

        applyStatusIcon(accessibilityDescription: "Dictating")

        let recordingID = AppLogger.shortID(prefix: "rec")
        diagnosticLog("PIPELINE", "recordingStarted", fields: ["recordingId": recordingID])

        textIntegrator.captureActiveApp(typesLive: activeModel.typesLive)

        if usesCleanup {
            Task.detached(priority: .medium) { [cleanup] in await cleanup.prepare() }
        }

        let activeSession = WeakBox<DictationSession>()
        let session = DictationSession(transcriber: transcriber, after: previousSessionDone) { [weak self] partial in
            guard let self = self else { return }
            let replacements = self.currentReplacements()
            let cleaned = TextCleanup.clean(partial, replacements: replacements)
            let stable = LiveText.stablePrefix(of: cleaned, holdBackWords: LiveText.holdBackWords(for: replacements))
            DispatchQueue.main.async {
                // A partial from a canceled session must not reach the next one.
                guard self.isCapturingAudio, self.session === activeSession.value else { return }
                self.textIntegrator.updateLiveText(stable)
            }
        }
        activeSession.value = session
        self.session = session
        previousSessionDone = session.completion

        recorderManager.startRecording(recordingID: recordingID, onAudio: { buffer in
            session.append(buffer)
        }, onNoAudio: { [weak self] in
            perfLog("AUDIO: No microphone audio received after restart; aborting recording")
            DispatchQueue.main.async {
                self?.abortDictationWithError(title: "Kein Audio")
            }
        }) { [weak self] error in
            if let error = error {
                perfLog("AUDIO: Dictation start failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.abortDictationWithError(title: "Dictation start failed")
                }
            }
        }
    }

    func stopRecordingFlow() {
        guard isRecording, !isProcessing else { return }
        isProcessing = true
        textIntegrator.stopWaitingForTarget()

        // Dictation can end in another app than it started in. The text then goes there, whole.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != textIntegrator.targetAppPID {
            textIntegrator.captureActiveApp(typesLive: false)
        }

        resetMenuBarIcon()

        // The last word is often still being spoken while the key goes up.
        recorderManager.stopRecording(after: 0.4) { [weak self] in
            self?.finishRecordingFlow()
        }
    }

    func finishRecordingFlow() {
        guard recorderManager.hasCapturedAudio, let session = session else {
            perfLog("PIPELINE: No microphone audio captured.")
            abortDictationWithError(title: "Audio recording empty")
            return
        }

        hudWindow?.showProcessing()

        let pipelineStart = Date()
        let cleansUp = usesCleanup
        let cleanup = self.cleanup
        let claudeKey = usesClaudeCleanup ? AnthropicKey.load() : nil
        let reasoning = claudeReasoning
        let prompt = claudePrompt
        let singleLine = textIntegrator.targetIsSingleLine
        Task { [weak self] in
            do {
                let transcription = try await session.finish()
                // The dictation is on screen right away, and the improved version follows.
                await MainActor.run {
                    guard let self, self.session === session else { return }
                    self.typeRemainingWords(of: transcription)
                }
                var polished = transcription
                var formatted = false
                let words = Double(transcription.split(separator: " ").count)
                if let claudeKey {
                    let start = Date()
                    if let answer = await ClaudeCleanup.polish(transcription, key: claudeKey, prompt: prompt, reasoning: reasoning,
                                                               singleLine: singleLine, timeout: reasoning.timeout + words * 0.01) {
                        polished = answer
                        formatted = true
                    }
                    perfLog(String(format: "CLEANUP: Claude %@ (%@) after %.2fs", formatted ? "used" : "skipped", reasoning.rawValue, Date().timeIntervalSince(start)))
                } else if cleansUp {
                    polished = await cleanup.polish(transcription, timeout: 5 + words * 0.03)
                }
                let text = polished
                let listsDone = formatted
                await MainActor.run {
                    // The user may have canceled during cleanup.
                    guard let self, self.session === session else { return }
                    self.deliver(text, transcription: transcription, listsDone: listsDone, pipelineStart: pipelineStart)
                }
            } catch {
                perfLog("PIPELINE: Transcription failed: \(error.localizedDescription)")
                await MainActor.run {
                    guard let self, self.session === session else { return }
                    self.abortDictationWithError(title: "Speech recognition failed")
                }
            }
        }
    }

    func cancelRecordingFlow() {
        isRecording = false
        session?.cancel()
        session = nil
        recorderManager.cancelRecording()
        textIntegrator.discardLiveText()
        hudWindow?.hideHUD()
        resetMenuBarIcon()
    }

    func abortDictationWithError(title: String) {
        isRecording = false
        session?.cancel()
        session = nil
        recorderManager.cancelRecording()
        resetMenuBarIcon()
        // Show compact error toast in HUD instead of large NSAlert
        hudWindow?.showErrorToast(title: title, message: "")
    }

    func typeRemainingWords(of transcription: String) {
        textIntegrator.updateLiveText(TextCleanup.clean(transcription, replacements: currentReplacements()))
    }

    /// `listsDone` means Claude already formatted the lists, which the rules must not redo.
    func deliver(_ polished: String, transcription: String, listsDone: Bool, pipelineStart: Date) {
        let delivering = session
        let replacements = currentReplacements()
        var finalText = TextCleanup.clean(polished, replacements: replacements)
        if usesListFormatting && !listsDone && !textIntegrator.targetIsSingleLine {
            finalText = ListFormatter.format(finalText)
        }
        let plainText = TextCleanup.clean(transcription, replacements: replacements)
        guard textIntegrator.isTypingLive, finalText != plainText else {
            finish(finalText, pipelineStart: pipelineStart)
            return
        }
        // Where typed text cannot be verified, it simply stays as dictated.
        textIntegrator.whenRewritable(to: finalText) { [weak self] rewritable in
            guard let self, self.session === delivering else { return }
            self.finish(rewritable ? finalText : plainText, pipelineStart: pipelineStart)
        }
    }

    func finish(_ finalText: String, pipelineStart: Date) {
        session = nil
        diagnosticLog(
            "PIPELINE",
            "transcribed",
            fields: [
                "durationSeconds": String(format: "%.3f", Date().timeIntervalSince(pipelineStart)),
                "outputChars": finalText.count
            ],
            privateFields: ["result": finalText]
        )

        isRecording = false

        // Text already typed at the cursor is brought to its final form.
        let pastesLineBreaks = textIntegrator.isTypingLive && finalText.contains("\n")
        if textIntegrator.isTypingLive, !pastesLineBreaks {
            textIntegrator.updateLiveText(finalText)
        }

        guard !finalText.isEmpty else {
            hudWindow?.showErrorToast(title: "No text detected", message: "")
            return
        }

        lastDictationText = finalText // Ephemeral RAM backup
        textIntegrator.setText(finalText)

        if pastesLineBreaks {
            // Pasted line breaks never send a chat message, unlike a typed Return.
            textIntegrator.finishLiveTextByPasting(
                finalText,
                onSuccess: { [weak self] in self?.hudWindow?.hideHUD() },
                onFailure: { [weak self] in self?.hudWindow?.showClipboardCapsule(text: finalText) }
            )
            return
        }

        if textIntegrator.isTypingLive {
            textIntegrator.whenTypingFinished { [weak self] in
                guard let self else { return }
                if self.textIntegrator.lostLiveTarget {
                    self.hudWindow?.showClipboardCapsule(text: finalText)
                } else {
                    self.hudWindow?.hideHUD()
                }
            }
            return
        }

        // The target was lost mid-dictation or takes a password, so the text is only offered for copying.
        if textIntegrator.lostLiveTarget || textIntegrator.targetIsSecure {
            hudWindow?.showClipboardCapsule(text: finalText)
            return
        }

        let result = textIntegrator.finalizeIntegration(
            onSuccess: { [weak self] in
                self?.hudWindow?.hideHUD()
            },
            onFailure: { [weak self] in
                self?.hudWindow?.showClipboardCapsule(text: self?.textIntegrator.accumulatedText ?? "")
            }
        )
        if result == .failed {
            hudWindow?.showClipboardCapsule(text: textIntegrator.accumulatedText)
        }
    }
}
