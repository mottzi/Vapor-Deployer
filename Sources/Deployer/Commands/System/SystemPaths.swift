import Foundation

/// Canonical install and runtime paths derived from setup inputs so steps and templates share one filesystem and routing contract.
struct SystemPaths {

    let serviceHome: String
    let installDirectory: String
    let appsRootDirectory: String
    let appDirectoryRelative: String
    let appDirectory: String
    let deployKeyPath: String
    let swiftlyHomeDirectory: String
    let swiftlyBinDirectory: String
    let swiftPath: String
    let webhookPath: String
    let deployerSocketPath: String
    let nginxSiteName: String
    let nginxSiteAvailable: String
    let nginxSiteEnabled: String
    let acmeWebroot: String
    let certbotRenewHook: String
    let appPublicDirectory: String
    let deployerctlBinary: String
    let deployerctlConfigDirectory: String
    let deployerctlConfig: String

    var deployerBinary: String { "\(installDirectory)/deployer" }
    var deployerConfig: String { "\(installDirectory)/deployer.json" }
    var deployerLog: String { "\(installDirectory)/deployer.log" }
    var appDeployDirectory: String { "\(appDirectory)/deploy" }

    /// Derives all managed paths from `serviceUser`, `appName`, and `panelRoute` so reruns stay deterministic across execution contexts.
    static func derive(serviceUser: String, appName: String, panelRoute: String) -> SystemPaths {
        
        let serviceHome = "/home/\(serviceUser)"
        let installDirectory = "\(serviceHome)/deployer"
        let appsRootDirectory = "\(serviceHome)/apps"
        let appDirectoryRelative = "../apps/\(appName)"
        let appDirectory = "\(appsRootDirectory)/\(appName)"
        let swiftlyHomeDirectory = "\(serviceHome)/.local/share/swiftly"
        let nginxSiteName = "deployer-\(appName)"

        return SystemPaths(
            serviceHome: serviceHome,
            installDirectory: installDirectory,
            appsRootDirectory: appsRootDirectory,
            appDirectoryRelative: appDirectoryRelative,
            appDirectory: appDirectory,
            deployKeyPath: "\(serviceHome)/.ssh/\(appName)_deploy_key",
            swiftlyHomeDirectory: swiftlyHomeDirectory,
            swiftlyBinDirectory: "\(swiftlyHomeDirectory)/bin",
            swiftPath: "\(swiftlyHomeDirectory)/bin:/usr/local/bin:/usr/bin:/bin",
            webhookPath: "/pushevent/\(appName)",
            deployerSocketPath: "\(panelRoute)/ws",
            nginxSiteName: nginxSiteName,
            nginxSiteAvailable: "/etc/nginx/sites-available/\(nginxSiteName).conf",
            nginxSiteEnabled: "/etc/nginx/sites-enabled/\(nginxSiteName).conf",
            acmeWebroot: "/var/www/certbot/\(appName)",
            certbotRenewHook: "/etc/letsencrypt/renewal-hooks/deploy/\(nginxSiteName)-reload-nginx.sh",
            appPublicDirectory: "\(appDirectory)/Public",
            deployerctlBinary: "/usr/local/sbin/deployerctl",
            deployerctlConfigDirectory: "/etc/deployer",
            deployerctlConfig: "/etc/deployer/deployerctl.conf"
        )
    }

}
