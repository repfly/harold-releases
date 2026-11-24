import Foundation
import Testing

@testable import HaroldKit

struct ProxyRouteTests {
    @Test("a good value adds one proxy")
    func goodValue() {
        guard #available(iOS 17, macOS 14, *) else { return }
        let route = ProxyRoute(environment: { ["HAROLD_PROXY": "127.0.0.1:47392"] })
        let configuration = URLSessionConfiguration.default
        route.apply(to: configuration)
        #expect(configuration.proxyConfigurations.count == 1)
    }

    @Test(
        "a bad value or no variable changes nothing",
        arguments: ["nope", "host:", ":80", "h:0", "h:70000", "h:x"]
    )
    func badValue(value: String) {
        let configuration = URLSessionConfiguration.default
        ProxyRoute(environment: { ["HAROLD_PROXY": value] }).apply(to: configuration)
        ProxyRoute(environment: { [:] }).apply(to: configuration)
        if #available(iOS 17, macOS 14, *) { #expect(configuration.proxyConfigurations.isEmpty) }
    }
}
