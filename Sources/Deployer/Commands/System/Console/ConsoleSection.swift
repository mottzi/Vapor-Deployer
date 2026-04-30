import Vapor

extension Console {

    func newLine() {
        output("")
    }
    
    func ruler(color: ConsoleColor? = nil) {
        let ruler = String(repeating: "━", count: TerminalWidth.current())
        output(ruler.consoleText(color: color))
    }

    func ruler(_ title: String, color: ConsoleColor? = nil) {
        
        let prefix = "━━━ "
        let fill = max(TerminalWidth.current() - (prefix.count + title.count + 1), 0)
        let string = "\(prefix)\(title) \(String(repeating: "━", count: fill))"
        
        output(string.consoleText(color: color, isBold: true))
    }

    func section(_ title: String) {
        newLine()
        output("  \(title)".consoleText(isBold: true))
    }

    func summaryRow(_ label: String, _ value: String) {
        output("  \(label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)")
    }

    func card(_ title: String, keyedValues: [(String, String)]) {
        
        newLine()
        ruler(title)
        newLine()
        
        for (key, value) in keyedValues {
            summaryRow(key, value)
        }
        
        newLine()
        ruler()
        newLine()
    }

    func lines(_ title: String, lines: [String]) {
        
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

    func stepHeader(title: String, index: Int, total: Int, color: ConsoleColor? = nil) {
        newLine()
        ruler("[\(index)/\(total)] \(title)", color: color)
    }

}
