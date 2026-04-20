import Foundation

enum SystemdUnitsTemplate {

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
        Environment="PANEL_PASSWORD=\(TemplateEscaping.environmentValue(context.panelPassword))"
        Restart=always
        RestartSec=2
        StandardOutput=append:\(paths.deployerLog)
        StandardError=append:\(paths.deployerLog)

        [Install]
        WantedBy=default.target
        """
    }

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
