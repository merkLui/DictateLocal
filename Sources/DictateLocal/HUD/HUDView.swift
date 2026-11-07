import SwiftUI

enum HUDDisplayMode {
    case recordingHold
    case recordingToggle
    case processing
    case clipboard
    case error
}

class HUDViewState: ObservableObject {
    @Published var displayMode: HUDDisplayMode = .recordingHold
    @Published var audioLevel: Float = 0.0
    /// Recent levels, newest last, so the waveform scrolls like a real signal instead of pulsing as one block.
    @Published var levelHistory: [Float] = Array(repeating: 0, count: WaveformView.barCount)

    func pushLevel(_ level: Float) {
        audioLevel = level
        levelHistory.removeFirst()
        levelHistory.append(level)
    }

    func resetLevels() {
        audioLevel = 0
        levelHistory = Array(repeating: 0, count: WaveformView.barCount)
    }
    @Published var textPreview: String = ""
    @Published var errorTitle: String = ""
    @Published var errorMessage: String = ""
}

struct HUDView: View {
    @ObservedObject var state: HUDViewState
    weak var appDelegate: AppDelegate?

    var body: some View {
        ZStack {
            if state.displayMode == .error {
                errorCapsule
            } else if state.displayMode == .clipboard {
                clipboardCapsule
            } else {
                recordingCapsule
            }
        }
        .padding(HUDWindow.edgeInset)
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Error Toast Capsule

    private var errorCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)

            Text(state.errorTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Clipboard Capsule

    private var clipboardCapsule: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            Text(state.textPreview)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                HUDIconButton(systemName: "doc.on.doc", help: "Copy") {
                    copyAndClose()
                }
                HUDIconButton(systemName: "xmark", help: "Dismiss") {
                    appDelegate?.cancelRecordingFlow()
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Recording / Processing Capsule

    private var recordingCapsule: some View {
        HStack(spacing: 8) {
            if state.displayMode == .recordingToggle {
                Button {
                    appDelegate?.cancelRecordingFlow()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            ZStack {
                if state.displayMode == .processing {
                    BouncingDotsView()
                } else {
                    WaveformView(levels: state.levelHistory)
                }
            }
            .frame(maxWidth: .infinity)

            if state.displayMode == .recordingToggle {
                Button {
                    appDelegate?.stopRecordingFlow()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Helpers

    private func copyAndClose() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(state.textPreview, forType: .string)
        appDelegate?.cancelRecordingFlow()
    }
}

// MARK: - HUD Icon Button

/// Small circular icon button for use inside a glass capsule (no nested glass).
struct HUDIconButton: View {
    let systemName: String
    let help: String
    var size: CGFloat = 28
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(isHovering ? 0.25 : 0.15)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    static let barCount = 13
    /// Oldest level first, newest last.
    var levels: [Float]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 3.0, height: barHeight(for: i))
            }
        }
        .animation(.easeOut(duration: 0.05), value: levels)
    }

    /// The newest level enters on the right and the signal scrolls to the left, like Voice Memos.
    private func barHeight(for index: Int) -> CGFloat {
        let historyIndex = levels.count - Self.barCount + index
        let level = levels.indices.contains(historyIndex) ? CGFloat(levels[historyIndex]) : 0
        let baseHeight: CGFloat = 6
        let maxHeight: CGFloat = 22
        return max(3, baseHeight + min(1, level * 1.2) * (maxHeight - baseHeight))
    }
}

// MARK: - Bouncing Dots View

struct BouncingDotsView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white)
                    .frame(width: 5.5, height: 5.5)
                    .offset(y: isAnimating ? -4 : 4)
                    .animation(
                        Animation.easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}
