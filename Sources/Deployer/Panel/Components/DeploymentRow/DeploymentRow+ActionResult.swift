import Mist

extension OperationCoordinator.StartResult {

    /// Preserves coordinator failure details while adapting accepted work to panel feedback.
    func actionResult(success: String) -> ActionResult {
        switch self {
            case .started: .success(success)
            case .operationBusy: .failure("A deployment is already running")
            case .failure(let message): .failure(message)
        }
    }

}
