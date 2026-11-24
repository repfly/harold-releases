import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Builds the `hello` message from the device, the app bundle and the install's device key.
struct HelloBuilder {
    static let deviceKeyDefaultsKey = "dev.alpr.harold.deviceKey"

    let defaults: UserDefaults
    let bundle: Bundle
    let processInfo: ProcessInfo
    let makeKey: () -> String

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo,
        makeKey: @escaping () -> String = { UUID().uuidString }
    ) {
        self.defaults = defaults
        self.bundle = bundle
        self.processInfo = processInfo
        self.makeKey = makeKey
    }

    /// The key is made once per install and kept in `UserDefaults`. It never goes to a log.
    func deviceKey() -> String {
        if let key = defaults.string(forKey: Self.deviceKeyDefaultsKey) { return key }
        let key = makeKey()
        defaults.set(key, forKey: Self.deviceKeyDefaultsKey)
        return key
    }

    func make() async -> Hello {
        let appID = bundle.bundleIdentifier ?? "unknown"
        let info = bundle.infoDictionary ?? [:]
        let version = processInfo.operatingSystemVersion
        return Hello(
            deviceKey: deviceKey(),
            deviceName: await deviceName(),
            model: modelIdentifier(),
            osVersion: "\(version.majorVersion).\(version.minorVersion)",
            simulator: isSimulator(),
            appID: appID,
            appName: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? appID,
            appVersion: (info["CFBundleShortVersionString"] as? String) ?? "0"
        )
    }

    private func deviceName() async -> String {
        #if canImport(UIKit)
            return await MainActor.run { UIDevice.current.name }
        #else
            return processInfo.hostName
        #endif
    }

    private func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
            return true
        #else
            return false
        #endif
    }

    private func modelIdentifier() -> String {
        if let simulated = processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
    }
}
