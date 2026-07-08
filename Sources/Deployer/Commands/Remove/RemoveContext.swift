import Foundation

/// Shared mutable state for one remove run, holding the identity, paths, and metadata needed to tear down an installation.
final class RemoveContext: ProvisioningContext {

    var serviceUser = ""
    var serviceUserUID: Int?
    var productName = ""
    var appName = ""
    var serviceBackend = ServiceBackend.systemd
    var certName = ""

    var paths: ProvisioningPaths?

    // Values read from deployerctl.conf for auto-discovery
    var nginxSiteAvailable: String?
    var nginxSiteEnabled: String?
    var acmeWebroot: String?
    var certbotRenewHook: String?
    var webhookPath: String?
    var githubWebhookSettingsURL: String?

}
