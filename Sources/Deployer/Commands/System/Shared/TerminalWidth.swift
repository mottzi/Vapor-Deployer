import Foundation

/// Shared terminal-width detection for command and deployment console rendering.
enum TerminalWidth {

    /// Detects terminal columns from `COLUMNS` or `tput cols`, defaulting to 80 and clamping to the fixed readability range [40, 100].
    static func current() -> Int {
        
        let raw = ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init)
            ?? tputColumns()
            ?? 80
        return min(max(raw, 40), 100)
    }

    /// Queries terminal column width via `tput cols`, returning nil on non-interactive or unavailable contexts.
    private static func tputColumns() -> Int? {
        
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tput", "cols"]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do { try process.run() }
        catch { return nil }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?.trimmed
        
        return value.flatMap(Int.init)
    }

}
