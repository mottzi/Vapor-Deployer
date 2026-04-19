import Vapor

enum SetupPrompts {

    static func askRequired(_ label: String, default defaultValue: String? = nil, console: any Console) -> String {
        while true {
            let value = prompt(label, default: defaultValue, console: console).trimmed
            let resolved = value.isEmpty ? (defaultValue ?? "") : value
            if !resolved.isEmpty { return resolved }
            console.warning("\(label) cannot be empty. Please try again.")
        }
    }

    static func askSecret(_ label: String, console: any Console) -> String {
        askSecretValue(label, console: console)
    }

    private static func askSecretValue(_ label: String, console: any Console) -> String {
        while true {
            let value = promptSecret(label, console: console).trimmed
            if !value.isEmpty {
                return value
            }
            console.warning("\(label) is required. Please try again.")
        }
    }

    static func askSecretConfirmed(_ label: String, console: any Console) -> String {
        while true {
            let first = askSecretValue(label, console: console)
            let second = promptSecret("Confirm \(label)", console: console)
            if first == second {
                return first
            }
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
        let value = prompt("\(label)\(suffix)", console: console).trimmed.lowercased()
        if value.isEmpty { return defaultYes }
        return ["y", "yes"].contains(value)
    }

    private static func prompt(_ label: String, default defaultValue: String? = nil, console: any Console) -> String {
        let defaultText = defaultValue.map { " [\($0)]" } ?? ""
        console.output("  \(label)\(defaultText): ".consoleText(), newLine: false)
        return console.input()
    }

    private static func promptSecret(_ label: String, console: any Console) -> String {
        console.output("  \(label): ".consoleText(), newLine: false)
        return console.input(isSecure: true)
    }

}
