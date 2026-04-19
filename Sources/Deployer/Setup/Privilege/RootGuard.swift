import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
import Darwin
#endif

enum RootGuard {

    static func requireRoot() throws {
        guard geteuid() == 0 else { throw SetupCommand.Error.notRoot }
    }

}
