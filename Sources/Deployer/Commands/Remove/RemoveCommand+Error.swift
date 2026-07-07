import Foundation

extension RemoveCommand {

    enum Error: DescribedError {

        case userDeletionFailed(String, String)
        case unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .userDeletionFailed(let user, let reason):
                "Unable to remove user '\(user)': \(reason)"

            case .unsafePath(let path):
                "Refusing to delete unsafe path: \(path)"
            }
        }

    }

}
