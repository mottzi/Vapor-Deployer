import Vapor
import Mist

extension TargetStatus {

    struct StopAction: Action {

        let name = "stop"
        let productName: String
        let broadcaster: TargetStatusBroadcaster

        func perform(targetID: UUID?, state: inout ComponentState, app: Application) async -> ActionResult {

            let lock: OperationLock
            do {
                lock = try OperationLock.acquire()
            } catch OperationError.anotherOperationInProgress {
                return .failure("A deployment is already running")
            } catch {
                return .failure(error.localizedDescription)
            }

            do {
                defer { lock.release() }
                let manager = app.deployer.serviceManager
                await broadcaster.setBadge(StatusState(.stopping))
                async let minHold: Void = Task.sleep(for: .seconds(1))
                app.logger.info("Stop action triggered via Panel for service: \(productName)")
                
                try await manager.stop(product: productName)
                try? await minHold

                let finalStatus = await manager.status(product: productName)
                await broadcaster.set(StatusState(finalStatus))

                return .success()
            } catch {
                let manager = app.deployer.serviceManager
                let recoveryStatus = await manager.status(product: productName)
                await broadcaster.set(StatusState(recoveryStatus))
                return .failure(error.localizedDescription)
            }
        }

    }

}
