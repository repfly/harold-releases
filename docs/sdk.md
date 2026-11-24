# Harold SDK

Send your app's logs and state to Harold on your Mac, and change feature flags in the running app without a rebuild.

There is one SDK for iOS (Swift Package) and one for Android (Maven). Both have the same small API: `start`, `log`, `state` and `overrides`.

- [iOS](#ios)
- [Android](#android)
- [Pick the builds that run the SDK](#pick-the-builds-that-run-the-sdk)
- [Pairing](#pairing)
- [Real devices](#real-devices)

---

## iOS

Needs iOS 15 or later. Proxy routing needs iOS 17 or later.

### 1. Add the package

In Xcode, choose **File › Add Package Dependencies…** and enter:

```
https://github.com/repfly/harold-releases
```

Pick **Up to Next Minor Version** from `0.5.1`, then add the **HaroldKit** library to your app target.

Or in `Package.swift`:

```swift
.package(url: "https://github.com/repfly/harold-releases", from: "0.5.1")
```

### 2. Start it

Call `start` once, early, for example in your `App` init or `application(_:didFinishLaunchingWithOptions:)`:

```swift
import HaroldKit

#if DEBUG
    Harold.start()
#endif
```

**You decide which builds start the SDK.** `#if DEBUG` is only an example. Use any compile condition you like (`#if DEBUG || QA`) or a runtime flag. Before `start`, the SDK does nothing: it opens no connection and reads nothing.

### 3. Log

```swift
Harold.log("user logged in", level: .info, category: "auth", metadata: ["method": "apple"])
```

The levels are `.debug`, `.info`, `.warning` and `.error`. Every line also goes to the Xcode console (`os_log`), so you can replace your own logger calls, or forward from your `AppLogger` to `Harold.log`.

`log` never blocks and never throws. While the Mac can't be reached, the SDK keeps the last 1000 lines and sends them later. Change the count with `Harold.start(bufferCapacity:)`.

### 4. Send state (optional)

```swift
Harold.state(["env": "QA", "userId": user.id, "screen": "Checkout"])
```

Harold shows the latest state next to the logs. If you want Harold's **Refresh** button to fetch fresh values, set a provider:

```swift
Harold.setStateProvider { ["screen": router.currentScreen] }
```

### 5. Read overrides (optional)

Harold can send string values to the running app, for example `tutorials=off`:

```swift
let showTutorials = Harold.overrides.bool("tutorials") ?? true

let observation = Harold.overrides.observe(key: "apiDelay") { key, value in
    // Runs on any thread, once for each change.
}
```

There are `string`, `bool` and `int` readers. Keep the `observation` and call `cancel()` to stop it.

### 6. Route traffic through the Harold proxy (optional)

To see your app's requests in Harold's **Traffic** screen, pass each session configuration to the SDK before you create the session:

```swift
let configuration = URLSessionConfiguration.default
Harold.apply(to: configuration)
let session = URLSession(configuration: configuration)
```

This works on iOS 17 or later when Harold launches the app with a proxy route. Without that route, or before `start`, it changes nothing. `URLSession.shared` can't be routed this way, so use your own session.

---

## Android

Needs minSdk 24.

### 1. Add the repository

In `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://raw.githubusercontent.com/repfly/harold-releases/main/maven")
    }
}
```

### 2. Add the dependencies

There are two artifacts with the same API. `harold-android` does the work. `harold-android-noop` does nothing and holds no networking code. **Pick one for each build variant:**

```kotlin
dependencies {
    debugImplementation("dev.alpr.harold:harold-android:0.5.1")
    releaseImplementation("dev.alpr.harold:harold-android-noop:0.5.1")
}
```

`debug` and `release` are examples. Use your own build types or flavors, for example `qaImplementation(...)` or `stagingDebugImplementation(...)`.

### 3. Start it and log

```kotlin
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Harold.start(this)
    }
}

Harold.log("user logged in", Level.INFO, "auth", mapOf("method" to "google"))
Harold.state(mapOf("env" to "QA", "screen" to "Checkout"))
val showTutorials = Harold.overrides.bool("tutorials") ?: true
```

Every line also goes to Logcat.

### 4. Allow the connection to your Mac

The SDK talks to Harold over plain WebSocket on `127.0.0.1` (and `10.0.2.2` on an emulator), so it needs cleartext for those two addresses. In each variant that uses `harold-android`, for example `src/debug/AndroidManifest.xml`:

```xml
<application android:networkSecurityConfig="@xml/harold_network_security_config" />
```

The artifact ships this file. If your app already has its own network security config, add these two domains to it instead:

```xml
<domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">127.0.0.1</domain>
    <domain includeSubdomains="false">10.0.2.2</domain>
</domain-config>
```

### 5. See HTTPS traffic (optional)

To read HTTPS requests in Harold's **Traffic** screen, install the Harold CA as a user certificate on the device (Harold pushes the file from the **Traffic** panel). The shipped config trusts user certificates in debuggable builds only. **A non-debuggable variant, for example a QA release build, needs its own config** with `<certificates src="user" />` in its `<base-config>` trust anchors.

---

## Pick the builds that run the SDK

Harold doesn't decide this for you.

- **iOS:** the SDK code is in every build that links HaroldKit. Nothing runs until you call `Harold.start()`, so the compile condition or flag around that call is your switch. The inactive code adds about 20 KB to an App Store build.
- **Android:** pick `harold-android` or `harold-android-noop` for each variant. With `noop`, the release APK holds no Harold networking code.

## Pairing

The first time an app install connects, Harold shows a pairing request with a 6-digit code. The same code shows in the Xcode console or Logcat. Click **Allow** and pick the project. The device stays paired until you remove it in the project settings.

## Real devices

- **iPhone (iOS 17 or later):** build and run it from Harold once. That launch tells the app your Mac's address, and the app remembers it. The iPhone must be on the same Wi-Fi as the Mac, with **network access** turned on in Harold. Add `NSLocalNetworkUsageDescription` to the Info.plist of the builds that start the SDK, or iOS blocks the connection.
- **Android phone:** connect it with USB or with wireless debugging (pair it in Harold). Harold uses `adb reverse`, so the app still talks to `127.0.0.1`.
- Simulators and emulators work with no extra setup.
