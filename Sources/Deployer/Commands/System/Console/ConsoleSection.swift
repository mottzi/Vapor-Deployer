import Vapor

extension Console {

    func newLine() {
        output("")
    }
    
    func ruler(color: ConsoleColor? = nil) {
        let ruler = String(repeating: "━", count: terminalWidth)
        output(ruler.consoleText(color: color))
    }

    func ruler(_ title: String, color: ConsoleColor? = nil) {
        
        let prefix = "━━━ "
        let fill = max(terminalWidth - prefix.count + title.count + 1, 0)
        let string = "\(prefix)\(title) \(String(repeating: "━", count: fill))"
        
        output(string.consoleText(color: color, isBold: true))
    }

    func section(_ title: String) {
        newLine()
        output("  \(title)".consoleText(isBold: true))
    }

    func card(title: String, keyedValues: [(String, String)]) {
        
        newLine()
        ruler(title)
        newLine()
        
        for (key, value) in keyedValues {
            output("  \(key.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)")
        }
        
        newLine()
        ruler()
        newLine()
    }

    func lines(title: String, lines: [String]) {
        
        newLine()
        ruler(title)
        newLine()
        
        for line in lines {
            output("  \(line)")
        }
        
        newLine()
        ruler()
        newLine()
    }

    func successTitledRule(_ title: String) {
        newLine()
        ruler(title, color: .green)
    }

}

/// Console rendering helpers so each step presents progress and key configuration in a consistent visual format.
extension Console {
    
    /// Clamps detected terminal width to a readable range so card formatting remains stable across TTY environments.
    private var terminalWidth: Int {
        
        let raw = ProcessInfo.processInfo.environment["COLUMNS"]
            .flatMap(Int.init)
            ?? tputColumns()
            ?? 80
        
        return min(max(raw, 40), 100)
    }
    
    /// Falls back to querying terminal column width when `COLUMNS` is unavailable, returning nil on non-interactive contexts.
    private func tputColumns() -> Int? {
        
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tput", "cols"]
        process.standardOutput = output
        process.standardError = Pipe()
        
        do { try process.run() }
        catch { return nil }
        
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?.trimmed
        return value.flatMap(Int.init)
    }
    
}
