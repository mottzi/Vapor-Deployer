import Vapor

enum SetupPrompts {

    static func askRequired(_ label: String, default defaultValue: String? = nil, console: any Console) -> String {
        while true {
            let prompt = defaultValue.map { "\(label) [\($0)]" } ?? label
            let value = console.ask(prompt.consoleText()).trimmed
            let resolved = value.isEmpty ? (defaultValue ?? "") : value
            if !resolved.isEmpty { return resolved }
            console.warning("\(label) cannot be empty. Please try again.")
        }
    }

    static func askSecret(_ label: String, console: any Console) -> String {
        while true {
            let value = console.ask(label.consoleText(), isSecure: true).trimmed
            if !value.isEmpty { return value }
            console.warning("\(label) is required. Please try again.")
        }
    }

    static func askSecretConfirmed(_ label: String, console: any Console) -> String {
        while true {
            let first = askSecret(label, console: console)
            let second = console.ask("Confirm \(label)".consoleText(), isSecure: true)
            if first == second { return first }
            console.warning("Values did not match. Please try again.")
        }
    }

    static func askValidated(
        _ label: String,
        default defaultValue: String? = nil,
        warning: String,
        console: any Console,
        validate: (String) -> Bool
    ) -> String {

        while true {
            let value = askRequired(label, default: defaultValue, console: console)
            if validate(value) { return value }
            console.warning(warning)
        }
    }

    static func confirm(_ label: String, defaultYes: Bool, console: any Console) -> Bool {
        let suffix = defaultYes ? " [Y/n]" : " [y/N]"
        let value = console.ask((label + suffix).consoleText()).trimmed.lowercased()
        if value.isEmpty { return defaultYes }
        return ["y", "yes"].contains(value)
    }

}
