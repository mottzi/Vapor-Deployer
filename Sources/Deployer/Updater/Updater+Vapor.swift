import Vapor
import Mist

extension Deployer {

    func useUpdater(config: Configuration, deployerState: LiveState<DeployerState>) {
        updater = Updater(app: app, config: config, deployerState: deployerState)
    }

    var updater: Updater {
        get {
            if let updater = app.storage[UpdaterKey.self] { return updater }
            fatalError("Updater not initialized.")
        }
        nonmutating set {
            app.storage[UpdaterKey.self] = newValue
        }
    }

    private struct UpdaterKey: StorageKey { typealias Value = Updater }

}
