import AVFoundation
import DictateCore
import Foundation

let usage = """
Usage: DictateBench <file> [--fast]      stream an audio file through the real dictation session
       DictateBench <file> --repeat      run several sessions on one transcriber
       DictateBench --download <folder>  download a model without loading it
       DictateBench --cleanup <jsonl>    install Spokenly and clean each line's "src" field
       DictateBench --lists              format each line from stdin as a list
       DictateBench --claude [low]       clean each line from stdin with Claude; key in ANTHROPIC_API_KEY
       Add --ultra to use Parakeet Ultra instead of Nemotron. Unit tests run with scripts/test.sh.
"""

let speechModel: SpeechModel = CommandLine.arguments.contains("--ultra") ? .parakeetUltra : .nemotron

func stream(path: String, fast: Bool) async throws {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32, interleaved: false)
    let transcriber = speechModel.makeTranscriber()
    let loadStart = Date()
    try await transcriber.prepare()
    print(String(format: "load=%.2fs", Date().timeIntervalSince(loadStart)))

    let start = Date()
    var partials = 0
    var firstPartial: Double?
    let session = DictationSession(transcriber: transcriber) { partial in
        partials += 1
        if firstPartial == nil { firstPartial = Date().timeIntervalSince(start) }
        print(String(format: "[%6.2fs] %@", Date().timeIntervalSince(start), String(partial.suffix(60))))
    }

    let chunk = AVAudioFrameCount(file.fileFormat.sampleRate / 10)
    var sent = 0.0
    while file.framePosition < file.length {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
        try file.read(into: buffer, frameCount: chunk)
        session.append(buffer)
        sent += Double(buffer.frameLength) / file.fileFormat.sampleRate
        if !fast {
            let wait = sent - Date().timeIntervalSince(start)
            if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
        }
    }

    let finishStart = Date()
    let text = try await session.finish()
    print(String(format: "audio=%.1fs firstPartial=%.2fs partials=%d finish=%.3fs", sent, firstPartial ?? -1, partials, Date().timeIntervalSince(finishStart)))
    print("TEXT " + text)
}

/// Same transcriber for several dictations: a canceled one in between must leave no trace.
func repeatSessions(path: String) async throws {
    let transcriber = speechModel.makeTranscriber()
    try await transcriber.prepare()

    func run(previous: Task<Void, Never>?, cancel: Bool) async throws -> (String, Task<Void, Never>) {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path), commonFormat: .pcmFormatFloat32, interleaved: false)
        let session = DictationSession(transcriber: transcriber, after: previous) { _ in }
        let chunk = AVAudioFrameCount(file.fileFormat.sampleRate / 10)
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { break }
            try file.read(into: buffer, frameCount: chunk)
            session.append(buffer)
        }
        if cancel {
            session.cancel()
            return ("", session.completion)
        }
        return (try await session.finish(), session.completion)
    }

    let (first, firstDone) = try await run(previous: nil, cancel: false)
    let (_, canceledDone) = try await run(previous: firstDone, cancel: true)
    let (second, _) = try await run(previous: canceledDone, cancel: false)
    guard !first.isEmpty, first == second else {
        print("FAIL: sessions differ\n  first:  \(first)\n  second: \(second)")
        exit(1)
    }
    print("Repeat check passed (\(first.split(separator: " ").count) words)")
}

func footprintMB() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return Int(info.phys_footprint) / 1_000_000
}

/// Runs the real cleanup over test data, in JSON lines with a "src" field.
func runSpokenly(path: String) async throws {
    struct Row: Codable { var id: String; var src: String; var out: String }
    let cleanup = SpokenlyCleanup()
    let installStart = Date()
    try await cleanup.install { print(String(format: "install %.0f %%", $0 * 100)) }
    print(String(format: "install=%.1fs", Date().timeIntervalSince(installStart)))
    let loadStart = Date()
    await cleanup.prepare()
    print(String(format: "load=%.2fs footprint=%dMB", Date().timeIntervalSince(loadStart), footprintMB()))
    for line in try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n") {
        let row = try JSONDecoder().decode(Row.self, from: Data(line.utf8))
        let start = Date()
        let cleaned = await cleanup.polish(row.src, timeout: 30)
        print(String(format: "%@\t%.3f\t%@\t%@", row.id, Date().timeIntervalSince(start), cleaned == row.out ? "same" : "diff", cleaned.replacingOccurrences(of: "\n", with: "⏎")))
    }
    print("afterCleaning footprint=\(footprintMB())MB")
    await cleanup.unload()
    print("afterUnload footprint=\(footprintMB())MB")
    await cleanup.prepare()
    print("reloaded footprint=\(footprintMB())MB")
    await cleanup.unload()
    print("afterSecondUnload footprint=\(footprintMB())MB")
}

if let index = CommandLine.arguments.firstIndex(of: "--claude") {
    // One transcript per line on stdin, one cleaned result per line on stdout.
    let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
    let level = CommandLine.arguments.dropFirst(index + 1).first.flatMap(ClaudeCleanup.Reasoning.init(rawValue:)) ?? .low
    while let line = readLine() {
        let start = Date()
        let cleaned = await ClaudeCleanup.polish(line, key: key, reasoning: level, singleLine: false, timeout: 30)
        print(String(format: "%.2fs\t%@", Date().timeIntervalSince(start), cleaned?.replacingOccurrences(of: "\n", with: "⏎") ?? "(kept as spoken)"))
    }
} else if CommandLine.arguments.contains("--lists") {
    // One sentence per line on stdin, one formatted result per line on stdout.
    while let line = readLine() { print(ListFormatter.format(line).replacingOccurrences(of: "\n", with: "⏎")) }
} else if let index = CommandLine.arguments.firstIndex(of: "--cleanup") {
    try await runSpokenly(path: CommandLine.arguments[index + 1])
} else if let index = CommandLine.arguments.firstIndex(of: "--download") {
    try await speechModel.download(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
    print("Download finished")
} else if CommandLine.arguments.contains("--repeat") {
    try await repeatSessions(path: CommandLine.arguments[1])
} else if CommandLine.arguments.count > 1 {
    try await stream(path: CommandLine.arguments[1], fast: CommandLine.arguments.contains("--fast"))
} else {
    print(usage)
}
