import Vapor

/// Prompting helpers that enforce required, validated, and confirmed user input before setup proceeds.
extension Console {

    func askRequired(_ label: String, default defaultValue: String? = nil) -> String {
        
        while true {
            let value = setupPrompt(label, default: defaultValue).trimmed
            let resolved = value.isEmpty ? (defaultValue ?? "") : value
            if !resolved.isEmpty { return resolved }
            self.warning("\(label) cannot be empty. Please try again.")
        }
    }

    func askSecret(_ label: String) -> String {
        askSecretValue(label)
    }

    private func askSecretValue(_ label: String) -> String {
        while true {
            let value = setupPromptSecret(label).trimmed
            if !value.isEmpty {
                return value
            }
            self.warning("\(label) is required. Please try again.")
        }
    }

    func askSecretConfirmed(_ label: String) -> String {
        while true {
            let first = askSecretValue(label)
            let second = setupPromptSecret("Confirm \(label)")
            if first == second { return first }
            self.warning("Values did not match. Please try again.")
        }
    }

    func askValidated(
        _ label: String,
        default defaultValue: String? = nil,
        warning: String,
        validate: (String) -> Bool
    ) -> String {

        while true {
            let value = askRequired(label, default: defaultValue)
            if validate(value) { return value }
            self.warning(warning)
        }
    }

    func confirm(_ label: String, defaultYes: Bool) -> Bool {
        let suffix = defaultYes ? " [Y/n]" : " [y/N]"
        let value = setupPrompt("\(label)\(suffix)").trimmed.lowercased()
        if value.isEmpty { return defaultYes }
        return ["y", "yes"].contains(value)
    }

    private func setupPrompt(_ label: String, default defaultValue: String? = nil) -> String {
        let defaultText = defaultValue.map { " [\($0)]" } ?? ""
        self.output("  \(label)\(defaultText): ".consoleText(), newLine: false)
        return self.input()
    }

    private func setupPromptSecret(_ label: String) -> String {
        self.output("  \(label): ".consoleText(), newLine: false)
        return self.input(isSecure: true)
    }

}
