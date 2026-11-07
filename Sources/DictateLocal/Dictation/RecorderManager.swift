import Foundation
import AVFoundation

class RecorderManager: NSObject {
    private var audioEngine: AVAudioEngine?
    private var lastAudioLevel: Float = 0.0
    private let targetSampleRate = 16000
    private var recordingStartTime: Date?
    private var firstAudioChunkTime: Date?
    private var audioChunkCount = 0
    private var maxAudioLevel: Float = 0.0
    private var isActiveRecording = false
    private var restartAttempted = false
    private var currentOnAudio: ((AVAudioPCMBuffer) -> Void)?
    private var currentOnNoAudio: (() -> Void)?
    private var recordingID = "none"
    /// Changes on every start and cancel, so a delayed stop knows when it is outdated.
    private var recordingGeneration = 0

    // Metering support for live waveform animation
    var isRecording: Bool {
        return audioEngine?.isRunning ?? false
    }

    var hasCapturedAudio: Bool {
        return audioChunkCount > 0
    }

    func startRecording(recordingID: String, onAudio: @escaping (AVAudioPCMBuffer) -> Void, onNoAudio: (() -> Void)? = nil, completion: @escaping (Error?) -> Void) {
        self.recordingID = recordingID
        recordingGeneration += 1
        recordingStartTime = Date()
        firstAudioChunkTime = nil
        audioChunkCount = 0
        maxAudioLevel = 0
        isActiveRecording = true
        restartAttempted = false
        currentOnAudio = onAudio
        currentOnNoAudio = onNoAudio

        startAudioEngine(completion: completion)
        scheduleNoAudioWatchdog(delay: 0.5)
    }

    private func startAudioEngine(completion: @escaping (Error?) -> Void) {
        do {
            let engine = AVAudioEngine()
            MicrophoneSelection.apply(to: engine)
            let inputNode = engine.inputNode
            // After switching devices the node's output format still describes the default
            // microphone, so tap in the selected device's own rate and channel count.
            let hardwareFormat = inputNode.inputFormat(forBus: 0)
            let startTime = recordingStartTime ?? Date()

            guard let inputFormat = AVAudioFormat(standardFormatWithSampleRate: hardwareFormat.sampleRate, channels: hardwareFormat.channelCount),
                  let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(targetSampleRate), channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                completion(NSError(domain: "Unable to create audio converter", code: 500, userInfo: nil))
                return
            }

            self.audioEngine = engine

            inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.updateAudioLevel(from: buffer)

                guard let convertedBuffer = self.convert(buffer, with: converter, to: targetFormat),
                      convertedBuffer.frameLength > 0 else { return }

                self.audioChunkCount += 1
                if self.firstAudioChunkTime == nil {
                    self.firstAudioChunkTime = Date()
                    diagnosticLog("AUDIO", "firstChunk", fields: [
                        "recordingId": self.recordingID,
                        "afterSeconds": String(format: "%.3f", Date().timeIntervalSince(startTime))
                    ])
                }
                self.currentOnAudio?(convertedBuffer)
            }

            engine.prepare()
            try engine.start()
            completion(nil)
        } catch {
            perfLog("AUDIO: Failed to start engine: \(error.localizedDescription)")
            completion(error)
        }
    }

    /// Keeps the microphone open for `tail` seconds before stopping, so the last word spoken while
    /// the key goes up is still captured. `completion` runs on the main queue, unless canceled first.
    func stopRecording(after tail: TimeInterval = 0, completion: @escaping () -> Void) {
        isActiveRecording = false
        currentOnNoAudio = nil
        let generation = recordingGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + tail) { [weak self] in
            guard let self = self, self.recordingGeneration == generation else { return }
            if let engine = self.audioEngine, engine.isRunning {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
            self.currentOnAudio = nil
            self.logStopSummary(reason: "stopped")
            completion()
        }
    }

    func cancelRecording() {
        recordingGeneration += 1
        isActiveRecording = false
        currentOnNoAudio = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        currentOnAudio = nil
        logStopSummary(reason: "canceled")
    }

    /// Returns the average sound level in dB, normalized from 0.0 (silent) to 1.0 (loudest)
    func getAudioLevel() -> Float {
        return isRecording ? lastAudioLevel : 0.0
    }

    private func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: convertedBuffer, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return buffer
        }

        if let error = conversionError {
            perfLog("AUDIO: Conversion failed: \(error.localizedDescription)")
            return nil
        }
        return convertedBuffer
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channel = channelData[0]
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0.0
        for index in 0..<frameLength {
            sum += abs(channel[index])
        }
        lastAudioLevel = min(1.0, (sum / Float(frameLength)) * 12.0)
        maxAudioLevel = max(maxAudioLevel, lastAudioLevel)
    }

    private func logStopSummary(reason: String) {
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        diagnosticLog("AUDIO", "recorderSummary", fields: [
            "recordingId": recordingID,
            "reason": reason,
            "durationSeconds": String(format: "%.2f", duration),
            "chunks": audioChunkCount,
            "maxLevel": String(format: "%.3f", maxAudioLevel)
        ])
    }

    private func scheduleNoAudioWatchdog(delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.handleNoAudioWatchdog()
        }
    }

    private func handleNoAudioWatchdog() {
        guard isActiveRecording, audioChunkCount == 0 else { return }

        if !restartAttempted {
            restartAttempted = true
            diagnosticLog("AUDIO", "noAudioRestarting", fields: ["recordingId": recordingID])
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil

            startAudioEngine { error in
                if let error = error {
                    perfLog("AUDIO: Restart failed: \(error.localizedDescription)")
                }
            }
            scheduleNoAudioWatchdog(delay: 1.0)
            return
        }

        diagnosticLog("AUDIO", "noAudioUnavailable", fields: ["recordingId": recordingID])
        isActiveRecording = false
        let callback = currentOnNoAudio
        currentOnNoAudio = nil
        callback?()
    }
}
