import Foundation
import Testing

@testable import HaroldKit

private let variable = HaroldHostOrder.hostVariable

private func order(
    launch: String? = nil, stored: String? = nil, simulator: Bool = false,
    save: @escaping @Sendable (String) -> Void = { _ in }
) -> HaroldHostOrder {
    HaroldHostOrder(
        environment: launch.map { [variable: $0] } ?? [:], isSimulator: simulator,
        load: { stored }, save: save)
}

struct HostOrderTests {
    @Test("the order is launch variable, stored host, loopback")
    func fullOrder() {
        let hosts = order(launch: "10.0.0.5", stored: "10.0.0.6")
        let tried = (0..<4).map { _ in hosts.nextHost() }
        #expect(tried == ["10.0.0.5", "10.0.0.6", "127.0.0.1", "10.0.0.5"])
    }

    @Test("without the variable the stored host comes first; without both only the loopback is left")
    func missingParts() {
        #expect(order(stored: "10.0.0.6").candidates == ["10.0.0.6", "127.0.0.1"])
        #expect(order().candidates == ["127.0.0.1"])
        #expect(order(launch: "127.0.0.1", stored: "127.0.0.1").candidates == ["127.0.0.1"])
    }

    @Test("welcome stores the host of the attempt, and only when it is new")
    func storesAfterWelcome() {
        let saved = Locked<[String]>([])
        let hosts = order(launch: "10.0.0.5", stored: "10.0.0.5") { host in saved.withLock { $0.append(host) } }
        _ = hosts.nextHost()
        #expect(saved.withLock { $0 }.isEmpty)
        _ = hosts.nextHost()
        #expect(saved.withLock { $0 }.isEmpty)
        hosts.confirm()
        #expect(saved.withLock { $0 } == ["127.0.0.1"])
    }

    @Test("the launch hint shows once, on a real device with no host")
    func launchHint() {
        let device = order()
        #expect(device.takeLaunchHint())
        #expect(!device.takeLaunchHint())
        #expect(!order(simulator: true).takeLaunchHint())
        #expect(!order(launch: "10.0.0.5").takeLaunchHint())
        #expect(!order(stored: "10.0.0.5").takeLaunchHint())
    }
}
