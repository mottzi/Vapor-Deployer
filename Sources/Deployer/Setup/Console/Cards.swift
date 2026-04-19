import Vapor

enum SetupCards {

    static func titledRule(_ title: String, console: any Console) {
        console.output("")
        console.output("--- \(title) ".consoleText(color: .cyan, isBold: true))
    }

    static func card(title: String, kvs: [(String, String)], console: any Console) {
        console.output("")
        console.output(title.consoleText(isBold: true))
        for (key, value) in kvs {
            console.output("  \(key.padding(toLength: 22, withPad: " ", startingAt: 0)) \(value)")
        }
        console.output("")
    }

    static func lines(title: String, lines: [String], console: any Console) {
        console.output("")
        console.output(title.consoleText(isBold: true))
        for line in lines {
            console.output("  \(line)")
        }
        console.output("")
    }

}
