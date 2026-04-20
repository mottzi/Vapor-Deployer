import Vapor
import Foundation

/// Console rendering helpers for setup UX so each step presents progress and key configuration in a consistent visual format.
extension Console {

    /// Clamps detected terminal width to a readable range so card formatting remains stable across TTY environments.
    private static var terminalWidth: Int {
        let raw = ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init)
            ?? tputColumns()
            ?? 80
        return min(max(raw, 40), 100)
    }

    /// Falls back to querying terminal column width when `COLUMNS` is unavailable, returning nil on non-interactive contexts.
    private static func tputColumns() -> Int? {
        
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tput", "cols"]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?.trimmed
        return value.flatMap(Int.init)
    }

    private static func rule(character: Character = "━") -> String {
        String(repeating: String(character), count: terminalWidth)
    }

    private static func titledRuleText(_ title: String, character: Character = "━") -> String {
        
        let prefix = "\(character)\(character)\(character) "
        let used = prefix.count + title.count + 1
        let fill = max(terminalWidth - used, 0)
        
        return "\(prefix)\(title) \(String(repeating: String(character), count: fill))"
    }

    func banner() {
        self.output("")
        self.output(Self.rule().consoleText(color: .cyan))
        self.output("  Vapor Deployer · Setup".consoleText(color: .cyan, isBold: true))
        self.output(Self.rule().consoleText(color: .cyan))
        self.output("")
        self.output("  Installs the deployer + target app, configures services.".consoleText())
        self.output("  Provisions Nginx + TLS and wires the GitHub webhook.".consoleText())
        self.output("")
    }

    func titledRule(_ title: String) {
        self.output("")
        self.output(Self.titledRuleText(title).consoleText(color: .cyan, isBold: true))
    }

    func section(_ title: String) {
        self.output("")
        self.output("  \(title)".consoleText(isBold: true))
    }

    func card(title: String, kvs: [(String, String)]) {
        self.output("")
        self.output(Self.titledRuleText(title).consoleText(isBold: true))
        self.output("")
        for (key, value) in kvs {
            self.output("  \(key.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)".consoleText())
        }
        self.output("")
        self.output(Self.rule().consoleText())
        self.output("")
    }

    func lines(title: String, lines: [String]) {
        self.output("")
        self.output(Self.titledRuleText(title).consoleText(isBold: true))
        self.output("")
        for line in lines {
            self.output("  \(line)".consoleText())
        }
        self.output("")
        self.output(Self.rule().consoleText())
        self.output("")
    }

}
