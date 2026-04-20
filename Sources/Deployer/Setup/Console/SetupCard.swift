import Vapor
import Foundation

/// Console rendering helpers for setup UX so each step presents progress and key configuration in a consistent visual format.
enum SetupCard {

    /// Clamps detected terminal width to a readable range so card formatting remains stable across TTY environments.
    private static let terminalWidth: Int = {
        let raw = ProcessInfo.processInfo.environment["COLUMNS"].flatMap(Int.init)
            ?? tputColumns()
            ?? 80
        return min(max(raw, 40), 100)
    }()

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

    static func banner(console: any Console) {
        
        console.output("")
        console.output(rule().consoleText(color: .cyan))
        console.output("  Vapor Deployer · Setup".consoleText(color: .cyan, isBold: true))
        console.output(rule().consoleText(color: .cyan))
        console.output("")
        console.output("  Installs the deployer + target app, configures services.".consoleText())
        console.output("  Provisions Nginx + TLS and wires the GitHub webhook.".consoleText())
        console.output("")
    }

    static func titledRule(_ title: String, console: any Console) {
        console.output("")
        console.output(titledRuleText(title).consoleText(color: .cyan, isBold: true))
    }

    static func section(_ title: String, console: any Console) {
        console.output("")
        console.output("  \(title)".consoleText(isBold: true))
    }

    static func card(title: String, kvs: [(String, String)], console: any Console) {
        
        console.output("")
        console.output(titledRuleText(title).consoleText(isBold: true))
        console.output("")
        for (key, value) in kvs {
            console.output("  \(key.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)".consoleText())
        }
        console.output("")
        console.output(rule().consoleText())
        console.output("")
    }

    static func lines(title: String, lines: [String], console: any Console) {
        console.output("")
        console.output(titledRuleText(title).consoleText(isBold: true))
        console.output("")
        for line in lines {
            console.output("  \(line)".consoleText())
        }
        console.output("")
        console.output(rule().consoleText())
        console.output("")
    }

}
