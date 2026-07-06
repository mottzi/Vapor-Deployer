import Vapor
import Fluent

extension BinaryStore {

    /// Vapor Fluent middleware that automatically purges a deployment's binary from disk when its database row is deleted.
    struct CleanupMiddleware: AsyncModelMiddleware {

        typealias Model = Deployment

        let target: TargetConfiguration

        func delete(
            model: Deployment,
            force: Bool,
            on db: any Database,
            next: any AnyAsyncModelResponder
        ) async throws {
            
            try await next.delete(model, force: force, on: db)
            guard model.product == target.name else { return }
            
            let store = BinaryStore(target: target)
            try store.deleteBinary(for: model)
        }

    }

}
