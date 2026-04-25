import Foundation

/// Generates systemd user-unit files for deployer and managed app services from setup-derived runtime paths.
enum SystemdTemplate {

    /// Emits the deployer unit with explicit runtime environment and append-only log targets for user-scoped service management.
    static func deployerUnit(context: SetupContext) throws -> String {
        
        let paths = try context.requirePaths()
        
        return """
        [Unit]
        Description=Deployer
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=simple
        WorkingDirectory=\(paths.installDirectory)
        ExecStart=\(paths.deployerBinary) serve
        Environment="PATH=\(TemplateEscaping.environmentValue(paths.swiftPath))"
        Environment="HOME=\(TemplateEscaping.environmentValue(paths.serviceHome))"
        Environment="USER=\(TemplateEscaping.environmentValue(context.serviceUser))"
        Environment="GITHUB_WEBHOOK_SECRET=\(TemplateEscaping.environmentValue(context.webhookSecret))"
        Environment="PANEL_PASSWORD_HASH=\(TemplateEscaping.environmentValue(context.panelPasswordHash))"
        Restart=always
        RestartSec=2
        StandardOutput=append:\(paths.deployerLog)
        StandardError=append:\(paths.deployerLog)

        [Install]
        WantedBy=default.target
        """
    }

    /// Emits the managed app unit bound to the deployed binary and configured application port under the same service user.
    static func appUnit(context: SetupContext) throws -> String {
        
        let paths = try context.requirePaths()
        
        return """
        [Unit]
        Description=\(context.productName)
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=simple
        WorkingDirectory=\(paths.appDirectory)
        ExecStart=\(paths.appDeployDirectory)/\(context.productName) serve --port \(context.appPort)
        Environment="PATH=\(TemplateEscaping.environmentValue(paths.swiftPath))"
        Environment="HOME=\(TemplateEscaping.environmentValue(paths.serviceHome))"
        Environment="USER=\(TemplateEscaping.environmentValue(context.serviceUser))"
        Restart=always
        RestartSec=2
        StandardOutput=append:\(paths.appDeployDirectory)/\(context.productName).log
        StandardError=append:\(paths.appDeployDirectory)/\(context.productName).log

        [Install]
        WantedBy=default.target
        """
    }

}
