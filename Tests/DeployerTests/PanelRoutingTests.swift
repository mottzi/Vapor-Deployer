import Foundation
import NIOPosix
import Testing
@testable import deployer

struct PanelRoutingTests {

    @Test(arguments: ["/", "/panel", "/admin/deployer"])
    func generatedRoutesAgreeWithRuntime(panelRoute: String) throws {
        let context = SetupContext(eventLoopGroup: MultiThreadedEventLoopGroup.singleton)
        context.serviceUser = "appuser"
        context.appName = "example"
        context.productName = "Example"
        context.primaryDomain = "ops.example.com"
        context.aliasDomain = "www.ops.example.com"
        context.certName = "ops.example.com"
        context.panelRoute = panelRoute
        context.paths = .derive(serviceUser: context.serviceUser, appName: context.appName, panelRoute: panelRoute)

        let nginx = try NginxTemplate.tls(context: context)
        let json = try #require(try DeployerTemplate.encodeJSON(from: context))
        let config = try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
        let expectedSocket = panelRoute == "/" ? "/ws" : panelRoute + "/ws"
        #expect(config.panelRoute == panelRoute)
        #expect(config.socketPath == expectedSocket)
        #expect(nginx.contains("location = \(expectedSocket) {"))
        #expect(!nginx.contains("location = //"))
        #expect(nginx.contains("location = /pushevent/example {"))
        #expect(nginx.contains("proxy_set_header Upgrade $http_upgrade;"))
        if panelRoute == "/" {
            #expect(!nginx.contains("@app_upstream"))
            #expect(!nginx.contains("127.0.0.1:8080"))
            #expect(!nginx.contains("/home/appuser/apps/example/Public"))
            #expect(nginx.contains("location ^~ /control/ {"))
        } else {
            #expect(nginx.contains("location = \(panelRoute) {"))
            #expect(nginx.contains("location ^~ \(panelRoute)/ {"))
            #expect(nginx.contains("proxy_pass http://127.0.0.1:8080;"))
        }
    }

}
