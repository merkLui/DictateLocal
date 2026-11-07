import AVFoundation
import CoreAudio

/// The microphone chosen in Settings. Empty means the system default.
enum MicrophoneSelection {
    static let key = "input_device_uid"

    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
    }

    static var devices: [Device] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        .devices
        .map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Points the engine at the chosen microphone. Falls back to the default if it is gone.
    static func apply(to engine: AVAudioEngine) {
        guard let uid = UserDefaults.standard.string(forKey: key), !uid.isEmpty else { return }
        guard var deviceID = audioDeviceID(forUID: uid), let unit = engine.inputNode.audioUnit else {
            perfLog("AUDIO: Selected microphone unavailable; using system default")
            return
        }
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            perfLog("AUDIO: Could not select microphone (status \(status)); using system default")
        }
    }

    private static func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &cfUID) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                pointer,
                &size,
                &deviceID
            )
        }
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }
}
