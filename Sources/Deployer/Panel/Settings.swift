import Vapor

extension Panel {

    /// Renders the settings page with the current `.env` contents (or the submitted-but-rejected
    /// entries, when called from `handleSettingsSave` after a validation failure).
    func serveSettings(request: Request) async throws -> View {

        let store = EnvironmentStore(envFilePath: envFilePath)
        let entries = try store.load()
        
        let rows = entries.map() {
            SettingsContext.Row(
                key: $0.key,
                value: $0.value,
                error: nil
            )
        }
        
        let context = SettingsContext(
            deployer: settingsDeployerContext,
            target: settingsTargetContext,
            entries: rows,
            variableCount: rows.count,
            globalError: nil
        )
        
        return try await request.view.render("Deployer/DeployerSettings", context)
    }

    /// Accepts the full desired state of the `.env` file, rewrites it atomically, and POST-redirects
    /// back to the settings page. On validation failure, re-renders the page with the submitted
    /// values and per-row errors so the user does not lose their edits.
    func handleSettingsSave(request: Request) async throws -> Response {

        let form: SettingsForm
        
        do {
            form = try request.content.decode(SettingsForm.self)
        } catch {
            request.logger.warning("Failed to decode settings form: \(error)")
            
            let view = try await renderSettingsWithErrors(
                request: request,
                entries: [],
                issues: [],
                globalError: "Could not read form data. Please reload and try again."
            )
            
            return try await view.encodeResponse(for: request)
        }
        
        let entries = form.entries

        let store = EnvironmentStore(envFilePath: envFilePath)
        
        do {
            try store.save(entries.map { EnvironmentStore.Entry(key: $0.key, value: $0.value) }, logger: request.logger)
        } catch let EnvironmentStore.SaveError.validation(issues) {
            let view = try await renderSettingsWithErrors(request: request, entries: entries, issues: issues, globalError: nil)
            return try await view.encodeResponse(for: request)
        } catch let EnvironmentStore.SaveError.writeFailed(path, underlying) {
            request.logger.error("Failed to write env file at \(path): \(underlying)")
            
            let view = try await renderSettingsWithErrors(
                request: request,
                entries: entries,
                issues: [],
                globalError: "Could not write \(path). Check the deployer log."
            )
            
            return try await view.encodeResponse(for: request)
        }

        let defaultTarget = panelPath == "/" ? "/settings" : panelPath + "/settings"
        let target = form.next.flatMap { $0.isEmpty ? nil : $0 } ?? defaultTarget
        
        return request.redirect(to: target)
    }

}

extension Panel {

    /// Absolute path to the target app's `.env` file. The file is inside the per-app directory
    /// (which is also the process `WorkingDirectory`) so Vapor's `DotEnvFile.load()` finds it
    /// automatically at boot.
    var envFilePath: String { "\(config.target.directory)/.env" }

}

extension Panel {

    /// Re-renders the settings page after a save failure, preserving the user's submitted values
    /// and attaching per-row + global error messages.
    private func renderSettingsWithErrors(
        request: Request,
        entries: [SettingsForm.Entry],
        issues: [EnvironmentStore.ValidationIssue],
        globalError: String?
    ) async throws -> View {

        var rowErrors: [Int: String] = [:]
        var globalMessages: [String] = []
        if let globalError { globalMessages.append(globalError) }
        
        for issue in issues {
            if let rowIndex = issue.rowIndex {
                rowErrors[rowIndex] = [rowErrors[rowIndex], issue.message].compactMap { $0 }.joined(separator: " ")
            } else {
                globalMessages.append(issue.message)
            }
        }

        let rows = entries.enumerated().map() { index, entry in
            SettingsContext.Row(
                key: entry.key,
                value: entry.value,
                error: rowErrors[index]
            )
        }

        let context = SettingsContext(
            deployer: settingsDeployerContext,
            target: settingsTargetContext,
            entries: rows,
            variableCount: rows.count,
            globalError: globalMessages.isEmpty ? nil : globalMessages.joined(separator: " ")
        )
        
        return try await request.view.render("Deployer/DeployerSettings", context)
    }

    private var settingsDeployerContext: SettingsContext.Deployer {
        SettingsContext.Deployer(
            panelRoute: panelPath,
            repositoryWebPageURL: DeployerVersion.repositoryWebPageURL
        )
    }

    private var settingsTargetContext: SettingsContext.Target {
        SettingsContext.Target(
            name: config.target.name,
            repositoryURL: config.target.repositoryURL,
            envFilePath: envFilePath.displayPath
        )
    }

}

extension Panel {

    struct SettingsContext: Encodable {

        let deployer: Deployer
        let target: Target
        let entries: [Row]
        let variableCount: Int
        let globalError: String?

        struct Deployer: Encodable {
            let panelRoute: String
            let repositoryWebPageURL: String
        }

        struct Target: Encodable {
            let name: String
            let repositoryURL: String?
            let envFilePath: String
        }

        struct Row: Encodable {
            let key: String
            let value: String
            let error: String?
        }

    }

    /// Decoded form body from the settings page. Vapor's `URLEncodedFormDecoder` pairs `key[]=foo&value[]=bar`
    /// into parallel arrays by index. We zip them back into `Entry` pairs and drop fully-empty rows.
    struct SettingsForm: Content {

        let key: [String]?
        let value: [String]?
        let next: String?

        struct Entry {
            let key: String
            let value: String
        }

        var entries: [Entry] {
            
            let keys = key ?? []
            let values = value ?? []
            let count = max(keys.count, values.count)
            
            var result: [Entry] = []
            
            for index in 0..<count {
                let k = (index < keys.count ? keys[index] : "").trimmingCharacters(in: .whitespaces)
                let v = index < values.count ? values[index] : ""
                
                if k.isEmpty && v.isEmpty { continue }
                
                result.append(Entry(key: k, value: v))
            }
            
            return result
        }

    }

}
