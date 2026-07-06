import Foundation
import NIOCore
import NIOPosix

enum SocketProbe {
    /// Attempts a non-blocking TCP connection to host:port using SwiftNIO.
    /// Returns true if the port is open and listening within the timeout duration.
    static func canConnect(host: String, port: Int, timeoutMs: Int, on eventLoopGroup: any EventLoopGroup) async -> Bool {
        let bootstrap = ClientBootstrap(group: eventLoopGroup)
            .connectTimeout(.milliseconds(Int64(timeoutMs)))
        
        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            return false // NIO already cleaned up the socket on a failed connect
        }

        do {
            try await channel.close().get()
        } catch {
            // Close failures don't change the fact that the connection was successfully established.
        }
        return true
    }
}
