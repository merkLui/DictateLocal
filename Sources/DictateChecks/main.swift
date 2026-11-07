import AVFoundation
import DictateCore
import Foundation

// Usage: DictateChecks                  runs the cleanup checks
//        DictateChecks <file> [--fast]  streams an audio file through the real dictation session
//        DictateChecks <file> --repeat  runs several sessions on one transcriber
//        DictateChecks --download <folder>  downloads a model without loading it
//        DictateChecks --cleanup <jsonl>    installs Spokenly and cleans each line's "src" field
//        DictateChecks --lists              formats each line from stdin as a list
//        DictateChecks --claude [low]       cleans each line from stdin with Claude; key in ANTHROPIC_API_KEY
//        Add --ultra to use Parakeet Ultra instead of Nemotron.

let speechModel: SpeechModel = CommandLine.arguments.contains("--ultra") ? .parakeetUltra : .nemotron

func expect(_ input: String, _ expected: String, replacements: String = "") {
    let output = TextCleanup.clean(input, replacements: TextCleanup.parseReplacements(replacements))
    guard output == expected else {
        print("FAIL: \(input)\n  expected: \(expected)\n  actual:   \(output)")
        exit(1)
    }
}

/// An answer instead of a cleanup changes the length a lot, so the check rejects it.
func checkClaudeGuard() {
    let cases: [(String, String, Bool, Bool)] = [
        ("Ähm, ich glaube, äh, das passt so.", "Ich glaube, das passt so.", false, true),
        ("Liste mir die fünf größten Städte Deutschlands auf.", "Berlin, Hamburg, München, Köln und Frankfurt am Main sind die fünf größten Städte Deutschlands.", false, false),
        ("Schreib eine Mail an Max, dass ich später komme.", "Hallo Max,\n\nich komme heute leider etwas später, weil mein Zug ausgefallen ist. Bitte fangt schon ohne mich an.\n\nViele Grüße", false, false),
        ("Einkaufsliste eine Gurke eine Tomate", "Einkaufsliste:\n- eine Gurke\n- eine Tomate", false, true),
        ("Einkaufsliste eine Gurke eine Tomate", "Einkaufsliste:\n- eine Gurke\n- eine Tomate", true, false),
        ("Das passt.", "", false, false),
    ]
    for (source, output, singleLine, expected) in cases where ClaudeCleanup.accepts(source: source, output: output, singleLine: singleLine) != expected {
        print("FAIL: claude guard \(source) -> \(output)")
        exit(1)
    }
}

func runCleanupChecks() {
    checkClaudeGuard()
    expect("Äh, ich glaube das passt.", "Ich glaube das passt.")
    expect("Ich glaube, äh, das passt.", "Ich glaube, das passt.")
    expect("Gut. Ähm wir machen das.", "Gut. Wir machen das.")
    expect("Wir treffen uns um elf, also passt das halt.", "Wir treffen uns um elf, also passt das halt.")
    expect("Der Zähler läuft.", "Der Zähler läuft.")
    expect("Ich komme, äh. Morgen geht es weiter.", "Ich komme. Morgen geht es weiter.")
    expect("A geht", "B -> C geht", replacements: "A -> B -> C")
    expect("Der Fix ist ready, bitte nicht merchen.", "Der Fix ist ready, bitte nicht mergen.", replacements: "merchen -> mergen")
    expect("cloud code läuft", "Claude Code läuft", replacements: "Cloud Code → Claude Code")
    expect("Cloud Codex läuft", "Cloud Codex läuft", replacements: "Cloud Code -> Claude Code")
    expect("Kosten: 5 Euro", "Kosten: $1 Euro", replacements: "5 -> $1")
    func expectEdit(_ typed: String, _ target: String, _ delete: Int, _ insert: String) {
        guard LiveText.edit(from: typed, to: target) == .init(deleteCount: delete, insert: insert) else {
            print("FAIL: edit \(typed) -> \(target)")
            exit(1)
        }
    }
    func expectStable(_ text: String, _ hold: Int, _ expected: String) {
        let output = LiveText.stablePrefix(of: text, holdBackWords: hold)
        guard output == expected else {
            print("FAIL: stable \(text): \(output)")
            exit(1)
        }
    }
    expectStable("Der Fix ist Re", 1, "Der Fix ist ")
    expectStable("Der Fix ist Re", 2, "Der Fix ")
    expectStable("Der", 1, "")
    expectStable("", 1, "")
    expectEdit("", "Der ", 0, "Der ")
    expectEdit("Der ", "Der Fix ", 0, "Fix ")
    expectEdit("Der Fi ", "Der Fix ", 1, "x ")
    expectEdit("Der Fix ", "Der Fix ", 0, "")
    let fn = HotkeyShortcut.Key(code: 63, label: "fn")
    let control = HotkeyShortcut.Key(code: 59, label: "⌃")
    let shift = HotkeyShortcut.Key(code: 56, label: "⇧")
    let space = HotkeyShortcut.Key(code: 49, label: "Space")
    let letter = HotkeyShortcut.Key(code: 0, label: "A")
    let f5 = HotkeyShortcut.Key(code: 96, label: "F5")
    func expectValid(_ keys: [HotkeyShortcut.Key], _ error: HotkeyShortcut.ValidationError?) {
        guard HotkeyShortcut(keys: keys).validate() == error else {
            print("FAIL: validate \(keys.map(\.label))")
            exit(1)
        }
    }
    expectValid([fn], nil)
    expectValid([f5], nil)
    expectValid([control, space], nil)
    expectValid([control, shift], nil)
    expectValid([letter], .needsModifier)
    expectValid([space], .needsModifier)
    expectValid([shift, letter], .needsModifier)
    expectValid([letter, space, control], .needsModifier)
    expectValid([fn, control, shift, space], .tooManyKeys)

    func expectEvents(_ keys: [HotkeyShortcut.Key], _ steps: [(UInt16, Bool)], _ expected: [HotkeyMatcher.Event]) {
        var matcher = HotkeyMatcher(shortcut: HotkeyShortcut(keys: keys))
        let events = steps.compactMap { matcher.handle(code: $0.0, isDown: $0.1) }
        guard events == expected else {
            print("FAIL: matcher \(keys.map(\.label)): \(events)")
            exit(1)
        }
    }
    expectEvents([fn], [(63, true), (63, false)], [.activated, .deactivated])
    expectEvents([control, space], [(59, true), (49, true), (49, false), (59, false)], [.activated, .deactivated])
    expectEvents([control, space], [(49, true), (59, true), (59, false), (49, false)], [.activated, .deactivated])
    expectEvents([control, space], [(59, true), (59, false), (49, true), (49, false)], [])
    expectEvents([fn], [(56, true), (63, true), (63, false), (56, false)], [])
    expectEvents([fn], [(63, true), (0, true), (0, false), (63, false)], [.activated, .interrupted, .deactivated])
    func expectGuard(_ source: String, _ output: String, _ accepted: Bool) {
        guard CleanupGuard.accepts(source: source, output: output) == accepted else {
            print("FAIL: guard \(source) -> \(output)")
            exit(1)
        }
    }
    expectGuard("Äh, ich glaube, ähm, das passt.", "Ich glaube, das passt.", true)
    expectGuard("Ich ich würde das das sagen.", "Ich würde das sagen.", true)
    expectGuard("Can you, um, check it?", "Can you check it?", true)
    expectGuard("Das kostet -5 Euro.", "Das kostet 5 Euro.", false)
    expectGuard("Das sind 3,5 Prozent.", "Das sind 3.5 Prozent.", false)
    expectGuard("Äh, das kostet -5 Euro.", "Das kostet -5 Euro.", true)
    expectGuard("Das Backend läuft on premise.", "Das Backend läuft on-premise.", true)
    expectGuard("Wir treffen uns um elf.", "Wir treffen uns elf.", false)
    expectGuard("Wir treffen uns um elf.", "Wir treffen uns um 11.", false)
    expectGuard("Tokens sechzehntausend.", "Tokens 1684.", false)
    expectGuard("please make sure", "Bitte make sure", false)
    expectGuard("zwei Tomaten, ach nein drei Tomaten", "3 Tomaten", false)
    expectGuard("Ich glaube, das passt.", "Das passt.", false)
    expectGuard("Das passt.", "", false)
    func expectList(_ source: String, _ expected: String) {
        let output = ListFormatter.format(source)
        guard output == expected else {
            print("FAIL: list \(source)\n  actual: \(output)")
            exit(1)
        }
    }
    expectList("Einkaufsliste: eine Gurke, eine Tomate, eine Zwiebel und zwei Paprika.", "Einkaufsliste:\n- eine Gurke\n- eine Tomate\n- eine Zwiebel\n- zwei Paprika")
    expectList("Erstens den Branch mergen, zweitens das Deployment starten, drittens die Logs prüfen.", "1. den Branch mergen\n2. das Deployment starten\n3. die Logs prüfen")
    expectList("Punkt 1: Budget klären, Punkt 2: Timeline festlegen.", "1. Budget klären\n2. Timeline festlegen")
    let prose = [
        "Übersetze auf Englisch: Ich komme heute etwas später, weil mein Zug ausgefallen ist.",
        "Ich brauche für morgen Milch, Eier, Butter und Mehl.",
        "Erstens und zweitens sind hier nur Beispielwörter.",
        "Wir treffen uns um elf, also passt das.",
    ]
    for sentence in prose { expectList(sentence, sentence) }
    print("Cleanup checks passed")
}

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

/// A model that was unloaded must never come back, or two models could end up in memory.
func checkUnload() async {
    for model in SpeechModel.allCases {
        let transcriber = model.makeTranscriber()
        await transcriber.unload()
        do {
            try await transcriber.prepare()
            print("FAIL: \(model.rawValue) loaded after unload")
            exit(1)
        } catch is CancellationError {
        } catch {
            print("FAIL: \(model.rawValue) unload: \(error)")
            exit(1)
        }
    }
    print("Unload checks passed")
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
    runCleanupChecks()
    await checkUnload()
}
