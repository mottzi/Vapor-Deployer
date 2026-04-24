import Vapor
import Foundation

/// Detects if identifiers like App Name or Domain have changed since the last setup, and garabage collects orphaned state.
struct CleanupOrphansStep: SetupStep {

    let context: SetupContext
    let console: any Console

    let title = "Cleaning up orphaned resources"

    func run() async throws {
        
        guard let previous = context.previousMetadata else { return }
        
        try await cleanupOrphanedApp(previous: previous)
        detectOrphanedTLS(previous: previous)
    }

}

extension CleanupOrphansStep {

    private func cleanupOrphanedApp(previous: [String: String]) async throws {
        
        let oldAppName = previous["APP_NAME"] ?? ""
        let oldProductName = previous["PRODUCT_NAME"] ?? ""
        let oldServiceManagerStr = previous["SERVICE_MANAGER"] ?? ""
        
        guard !oldAppName.isEmpty, !oldProductName.isEmpty, !oldServiceManagerStr.isEmpty else { return }
        
        let paths = try context.requirePaths()
        let productChanged = oldProductName != context.productName
        let appNameChanged = oldAppName != context.appName

        guard productChanged || appNameChanged else { return }
        
        if productChanged {
            console.warning("Detected product change from '\(oldProductName)' to '\(context.productName)'. Cleaning up old service artifacts.")
        }
        
        if appNameChanged {
            console.warning("Detected app name change from '\(oldAppName)' to '\(context.appName)'. Cleaning up old checkout and SSH deploy key.")
        }
        
        if productChanged, let oldServiceManager = ServiceManagerKind(rawValue: oldServiceManagerStr) {
            try await stopAndRemoveOldService(oldProductName: oldProductName, serviceManager: oldServiceManager, paths: paths)
        }
        
        if appNameChanged {
            try await removeOldCheckout(oldAppName: oldAppName, paths: paths)
            try await removeOldDeployKey(oldAppName: oldAppName, paths: paths)
        }
    }

    private func detectOrphanedTLS(previous: [String: String]) {
        
        let oldPrimaryDomain = previous["PRIMARY_DOMAIN"] ?? ""
        let oldCertName = previous["CERT_NAME"] ?? ""
        
        guard !oldPrimaryDomain.isEmpty, !oldCertName.isEmpty else { return }
        
        if oldPrimaryDomain == context.primaryDomain { return }

        console.warning("Detected primary domain change from '\(oldPrimaryDomain)' to '\(context.primaryDomain)'.")
        
        guard oldCertName != context.certName else {
            console.print("Keeping certificate lineage '\(oldCertName)' because it may still be reused by the updated configuration.")
            return
        }
        
        context.orphanedPrimaryDomain = oldPrimaryDomain
        context.orphanedCertNameToDelete = oldCertName
        console.print("Will offer optional cleanup for old certificate lineage '\(oldCertName)' after TLS setup succeeds.")
    }

}

extension CleanupOrphansStep {

    private func stopAndRemoveOldService(
        oldProductName: String,
        serviceManager: ServiceManagerKind,
        paths: SystemPaths
    ) async throws {

        let configurator = serviceManager.makeConfigurator(shell: shell, paths: paths)
        await configurator.disable([oldProductName])
        await configurator.removeConfigs(for: [oldProductName])
    }

    private func removeOldCheckout(oldAppName: String, paths: SystemPaths) async throws {
        
        let oldCheckoutPath = "\(paths.appsRootDirectory)/\(oldAppName)"
        try? SystemFileSystem.removeIfPresent(oldCheckoutPath)
    }

    private func removeOldDeployKey(oldAppName: String, paths: SystemPaths) async throws {
        
        let oldDeployKeyPath = "\(paths.serviceHome)/.ssh/\(oldAppName)_deploy_key"
        try? SystemFileSystem.removeIfPresent(oldDeployKeyPath)
        try? SystemFileSystem.removeIfPresent("\(oldDeployKeyPath).pub")
    }

}
