import Foundation

enum AppLogger {
    static var logFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return baseURL
            .appendingPathComponent("DictateLocal", isDirectory: true)
            .appendingPathComponent("performance.log")
    }
    
    static func exportLog(to destinationURL: URL) throws {
        let sourceURL = logFileURL
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        if fileManager.fileExists(atPath: sourceURL.path) {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } else {
            try "No performance log exists yet.\n".write(to: destinationURL, atomically: true, encoding: .utf8)
        }
    }
    
    static func clearLog() {
        let fileURL = logFileURL
        // Truncate to 0 bytes — keeps the file so logging continues immediately
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            defer { fileHandle.closeFile() }
            fileHandle.truncateFile(atOffset: 0)
        } else {
            // File doesn't exist yet — nothing to clear
        }
        perfLog("LOG: Cleared by user")
    }

    static var usesPrivacyLogging: Bool {
        UserDefaults.standard.object(forKey: "privacy_logging") as? Bool ?? true
    }

    static func shortID(prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8))"
    }
}

private let logLock = NSLock()

func perfLog(_ message: String) {
    logLock.lock()
    defer { logLock.unlock() }
    
    let logMessage = "[PERF] \(message)\n"
    print("[PERF] \(message)") // Console fallback
    
    let fileURL = AppLogger.logFileURL
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    
    if let data = logMessage.data(using: .utf8) {
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}

func diagnosticLog(
    _ category: String,
    _ event: String,
    fields: [String: CustomStringConvertible?] = [:],
    privateFields: [String: CustomStringConvertible?] = [:]
) {
    var merged = fields
    if !AppLogger.usesPrivacyLogging {
        privateFields.forEach { merged[$0.key] = $0.value }
    }

    let renderedFields = merged
        .sorted { $0.key < $1.key }
        .compactMap { key, value -> String? in
            guard let value else { return nil }
            return "\(key)=\(sanitizeLogValue(value.description))"
        }
        .joined(separator: " ")

    if renderedFields.isEmpty {
        perfLog("\(category): event=\(event)")
    } else {
        perfLog("\(category): event=\(event) \(renderedFields)")
    }
}

private func sanitizeLogValue(_ value: String) -> String {
    let sanitized = value
        .replacingOccurrences(of: "\r", with: "↵")
        .replacingOccurrences(of: "\n", with: "↵")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if sanitized.contains(" ") || sanitized.contains("=") {
        return "\"\(sanitized.replacingOccurrences(of: "\"", with: "'"))\""
    }
    return sanitized
}
