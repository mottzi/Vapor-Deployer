import Foundation

/// Generates Supervisor program definitions for the deployer and managed app services with setup-owned runtime paths.
enum SupervisorTemplate {

    /// Emits the deployer program stanza including credentials required by webhook and panel-auth flows.
    static func deployerProgram(context: SetupContext) throws -> String {
        
        let paths = try context.requirePaths()
        
        return """
        [program:deployer]
        directory=\(paths.installDirectory)
        command=\(paths.deployerBinary) serve
        user=\(context.serviceUser)
        environment=PATH="\(TemplateEscaping.environmentValue(paths.swiftPath))",HOME="\(TemplateEscaping.environmentValue(paths.serviceHome))",USER="\(TemplateEscaping.environmentValue(context.serviceUser))",GITHUB_WEBHOOK_SECRET="\(TemplateEscaping.environmentValue(context.webhookSecret))",PANEL_PASSWORD="\(TemplateEscaping.environmentValue(context.panelPassword))"
        autorestart=true
        redirect_stderr=true
        stdout_logfile=\(paths.deployerLog)
        """
    }

    /// Emits the managed app program stanza that launches the deployed binary on the configured app port.
    static func appProgram(context: SetupContext) throws -> String {
        
        let paths = try context.requirePaths()
        
        return """
        [program:\(context.productName)]
        directory=\(paths.appDirectory)
        command=\(paths.appDeployDirectory)/\(context.productName) serve --port \(context.appPort)
        user=\(context.serviceUser)
        environment=PATH="\(TemplateEscaping.environmentValue(paths.swiftPath))",HOME="\(TemplateEscaping.environmentValue(paths.serviceHome))",USER="\(TemplateEscaping.environmentValue(context.serviceUser))"
        autorestart=true
        redirect_stderr=true
        stdout_logfile=\(paths.appDeployDirectory)/\(context.productName).log
        """
    }

}
