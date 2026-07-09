import NIOCore
import NIOPosix

extension Host {

    /// Provides transport-level host probes without owning caller-specific retry or health policy.
    enum Network {

        /// Confirms that a TCP listener accepts one bounded connection and closes it immediately.
        static func canConnect(
            host: String,
            port: Int,
            timeout: TimeAmount,
            on eventLoopGroup: any EventLoopGroup
        ) async -> Bool {

            let bootstrap = ClientBootstrap(group: eventLoopGroup)
                .connectTimeout(timeout)

            let channel = try? await bootstrap.connect(host: host, port: port).get()
            guard let channel else { return false }
            
            try? await channel.close().get()
            return true
        }

    }

}
