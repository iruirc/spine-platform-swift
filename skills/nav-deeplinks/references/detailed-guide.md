# nav-deeplinks — detailed guide

## Contents

- Link Type Decision
- Universal Links Setup
- The DeepLink Parser
- Entry Points
- Cold Start & Pending Route
- Deferred Deep Links
- Testing

## Link Type Decision

Ship **both** a custom scheme and Universal Links; map both to one `Route`.

Custom scheme — `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key><string>com.example.app</string>
    <key>CFBundleURLSchemes</key><array><string>myapp</string></array>
  </dict>
</array>
```

Custom scheme is unauthenticated and hijackable (any app may register the same
scheme). Never use it as a security boundary; OAuth callbacks should use a
unique scheme and still verify `state`.

Universal Links survive "app not installed" (browser opens the `https://` URL),
are domain-bound (not hijackable), and are the default for any user-facing or
shared link.

## Universal Links Setup

1. Associated Domains entitlement:

```
applinks:example.com
applinks:www.example.com
```

2. `apple-app-site-association` (AASA) — served at
`https://example.com/.well-known/apple-app-site-association`, `Content-Type:
application/json`, **no redirect**, reachable without auth:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["ABCDE12345.com.example.app"],
        "components": [
          { "/": "/item/*",    "comment": "item detail" },
          { "/": "/profile/*", "comment": "profile" },
          { "/": "/promo",     "?": { "code": "*" } }
        ]
      }
    ]
  }
}
```

3. Apple's CDN caches AASA — bump it on deploy; verify via
`https://app-site-association.cdn-apple.com/a/v1/example.com`.

Common AASA failures: wrong `Content-Type`, served behind a 301/302,
`appIDs` not `TeamID.BundleID`, file not at `.well-known`, JSON invalid.

## The DeepLink Parser

Pure, `Sendable`, no UI, no navigation, no singletons. The `Route` enum is
owned by the navigation layer's public contract; the parser only produces it.
`Route` is `Hashable`, which `NavigationPath.append`, `NavigationStack(path:)`
and `navigationDestination(for:)` require.

<!-- typecheck -->
```swift
import Foundation

enum Route: Hashable, Sendable {
    case item(id: String)
    case profile(userId: String)
    case promo(code: String)
}

enum DeepLinkParser {
    private static let universalLinkHosts: Set<String> = [
        "example.com",
        "www.example.com"
    ]

    static func parse(_ url: URL) -> Route? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        // Normalize custom scheme and https:// to the same path shape.
        // myapp://item/42            -> host "item", path "/42"
        // https://example.com/item/42 -> path "/item/42"
        guard let scheme = comps.scheme?.lowercased() else { return nil }
        let segments: [String]
        switch scheme {
        case "myapp":
            segments = ([comps.host].compactMap { $0 })
                + comps.path.split(separator: "/").map(String.init)
        case "https":
            guard let host = comps.host?.lowercased(),
                  universalLinkHosts.contains(host)
            else { return nil }
            segments = comps.path.split(separator: "/").map(String.init)
        default:
            return nil
        }

        switch segments.first {
        case "item":
            guard let id = segments[safe: 1], !id.isEmpty, id.count <= 64
            else { return nil }
            return .item(id: id)
        case "profile":
            guard let uid = segments[safe: 1], !uid.isEmpty else { return nil }
            return .profile(userId: uid)
        case "promo":
            guard let code = comps.queryItems?
                .first(where: { $0.name == "code" })?.value, !code.isEmpty
            else { return nil }
            return .promo(code: code)
        default:
            return nil   // unknown / old link -> the caller does not navigate
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
```

Validate every extracted value (non-empty, length/bounds). The URL is
untrusted input; `nil` is a normal, tested outcome.

## Entry Points

One router, every source funnels in. The router owns timing and the auth gate;
the navigation layer hands it a closure once it exists, so this skill stays
navigation-agnostic.

<!-- typecheck -->
```swift
import CoreSpotlight

@MainActor
final class DeepLinkRouter {
    private var pending: Route?
    private var navigate: ((Route) -> Void)?   // -> arch-coordinator / SwiftUI Router
    private let isAuthed: () -> Bool
    private let requiresAuth: (Route) -> Bool

    init(isAuthed: @escaping () -> Bool,
         requiresAuth: @escaping (Route) -> Bool) {
        self.isAuthed = isAuthed
        self.requiresAuth = requiresAuth
    }

    // Custom scheme; in SwiftUI a Universal Link too
    func handle(_ url: URL) {
        // unknown link: stay where the app is
        guard let route = DeepLinkParser.parse(url) else { return }
        dispatch(route)
    }

    // Universal Link in UIKit, Handoff, Spotlight
    func handle(_ activity: NSUserActivity) {
        if activity.activityType == CSSearchableItemActionType {
            // the app indexes each item with its link URL as uniqueIdentifier
            guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let url = URL(string: id) else { return }
            handle(url)
        } else if let url = activity.webpageURL {
            handle(url)
        }
    }

    // Quick action — already an intent
    @discardableResult
    func handle(shortcut type: String) -> Bool {
        switch type {
        case "com.example.app.newItem": dispatch(.item(id: "new")); return true
        default: return false
        }
    }

    func appBecameReady(navigate: @escaping (Route) -> Void) {
        self.navigate = navigate
        replayPending()
    }

    func userDidLogIn() {
        replayPending()
    }

    func userDidLogOut() {
        pending = nil   // a link buffered for one session must not open in the next
    }

    private func replayPending() {
        guard let route = pending else { return }
        pending = nil
        dispatch(route)
    }

    private func dispatch(_ route: Route) {
        guard let navigate else { pending = route; return }
        if requiresAuth(route) && !isAuthed() { pending = route; return }
        navigate(route)
    }
}
```

The app delegate owns the app-scope graph and takes notification taps, a cold
start's included. Its delegate method is `nonisolated` because
`UNNotificationResponse` is not `Sendable`; it hands the router a `URL`:

<!-- typecheck -->
```swift
import UIKit
import UserNotifications

final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let dependencies = AppDependencyContainer()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // before launch ends, or the tap that launched the app is lost
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let s = userInfo["deeplink"] as? String, let url = URL(string: s) else { return }
        await dependencies.deepLinks.handle(url)
    }
}
```

UIKit scene. A cold start's URL, activity or shortcut arrives only in
`connectionOptions`; the other three methods fire for a scene that is already
connected. The router buffers what arrives before the coordinator is attached:

<!-- typecheck -->
```swift
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: AppCoordinator?

    private var dependencies: AppDependencyContainer {
        (UIApplication.shared.delegate as! AppDelegate).dependencies
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let deepLinks = dependencies.deepLinks
        if let url = connectionOptions.urlContexts.first?.url { deepLinks.handle(url) }
        if let activity = connectionOptions.userActivities.first { deepLinks.handle(activity) }
        if let item = connectionOptions.shortcutItem { deepLinks.handle(shortcut: item.type) }
        // connectionOptions.notificationResponse: the app delegate receives the same tap

        let window = UIWindow(windowScene: windowScene)
        let coordinator = dependencies.makeAppCoordinator(window: window)
        self.window = window
        self.coordinator = coordinator
        coordinator.start()
        deepLinks.appBecameReady { [weak coordinator] in coordinator?.handleDeepLink($0) }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url { dependencies.deepLinks.handle(url) }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        dependencies.deepLinks.handle(userActivity)
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(dependencies.deepLinks.handle(shortcut: shortcutItem.type))
    }
}
```

SwiftUI. `onOpenURL` receives custom-scheme URLs and Universal Links alike,
`onContinueUserActivity` receives Spotlight and Handoff activities, and the app
delegate above takes notification taps. `path` stands in for the navigation
layer. `@main` goes on this `App`, or on `AppDelegate` in a UIKit app:

<!-- typecheck -->
```swift
import SwiftUI
import CoreSpotlight

struct ExampleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var path: [Route] = []

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                HomeView()
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            .onOpenURL { appDelegate.dependencies.deepLinks.handle($0) }
            .onContinueUserActivity(CSSearchableItemActionType) {
                appDelegate.dependencies.deepLinks.handle($0)
            }
            .onAppear {
                appDelegate.dependencies.deepLinks.appBecameReady { path.append($0) }
            }
        }
    }
}
```

## Cold Start & Pending Route

Sequence for a link from a *killed* app:

1. OS launches the app and hands over the link: in `connectionOptions` of
   `scene(_:willConnectTo:options:)` for a UIKit scene, to `onOpenURL` /
   `onContinueUserActivity` in SwiftUI, to
   `userNotificationCenter(_:didReceive:)` for a notification tap.
2. `router.handle` parses; with no navigation layer attached yet it stores
   `pending`.
3. The scene builds its root + restores auth → calls
   `router.appBecameReady(navigate:)` → `pending` replays once.
4. If the route needs auth and the user is logged out, it stays buffered;
   `router.userDidLogIn()` after a successful login replays it.
5. `router.userDidLogOut()` drops whatever is still buffered.

Reset-vs-preserve: per route decide whether arrival resets the nav stack
(e.g. promo → fresh) or pushes onto the current stack (e.g. item from a list).
Record the decision in `spine-toolkit:feature-requirements` and verify in
`spine-toolkit:ops-checklist`.

## Deferred Deep Links

User taps a marketing link, has no app, installs from the App Store, opens —
the original link is lost (App Store does not pass it through). Options:

- **Universal Link first** — if the app *is* installed there is no deferral
  problem; this only matters for the not-installed path.
- Attribution SDK (Branch, AppsFlyer, Adjust) stores the click server-side
  keyed by a fingerprint / paste of a clipboard token, then returns the
  intended `Route` on first launch via its callback → feed into the same
  `DeepLinkParser` / `Route`.
- Apple Ads Attribution / `AdServices` token for campaign attribution only —
  not a content router.

Keep the SDK at the edge: its callback yields a `URL` or `Route`, then the
normal funnel + cold-start buffer takes over. Do not let an attribution SDK
own navigation.

## Testing

Parser table test:

<!-- typecheck -->
```swift
import XCTest

final class DeepLinkParserTests: XCTestCase {
    func test_parse() {
        let cases: [(String, Route?)] = [
            ("myapp://item/42",                       .item(id: "42")),
            ("https://example.com/item/42",           .item(id: "42")),
            ("https://evil.example/item/42",          nil),
            ("ftp://example.com/item/42",             nil),
            ("https://example.com/item/",             nil),
            ("https://example.com/unknown",           nil),
            ("https://example.com/promo?code=ABC",    .promo(code: "ABC")),
            ("myapp://item/" + String(repeating: "x", count: 999), nil),
        ]
        for (s, expected) in cases {
            XCTAssertEqual(DeepLinkParser.parse(URL(string: s)!), expected, s)
        }
    }
}
```

Cold-start replay. The router is `@MainActor`, so its test class is too:

<!-- typecheck -->
```swift
@MainActor
final class DeepLinkRouterTests: XCTestCase {
    func test_coldStart_replaysOnce() {
        var routed: [Route] = []
        let router = DeepLinkRouter(isAuthed: { true }, requiresAuth: { _ in false })
        router.handle(URL(string: "myapp://item/7")!)   // not ready -> buffered
        XCTAssertTrue(routed.isEmpty)
        router.appBecameReady { routed.append($0) }
        XCTAssertEqual(routed, [.item(id: "7")])
        router.appBecameReady { routed.append($0) }     // no duplicate
        XCTAssertEqual(routed, [.item(id: "7")])
    }
}
```

Auth gate and logout:

<!-- typecheck -->
```swift
extension DeepLinkRouterTests {
    func test_authGate_buffersUntilLogin() {
        var routed: [Route] = []
        var loggedIn = false
        let router = DeepLinkRouter(isAuthed: { loggedIn }, requiresAuth: { _ in true })
        router.appBecameReady { routed.append($0) }
        router.handle(URL(string: "myapp://profile/me")!)   // logged out -> buffered
        XCTAssertTrue(routed.isEmpty)
        loggedIn = true
        router.userDidLogIn()
        XCTAssertEqual(routed, [.profile(userId: "me")])
    }

    func test_logout_dropsPending() {
        var routed: [Route] = []
        var loggedIn = false
        let router = DeepLinkRouter(isAuthed: { loggedIn }, requiresAuth: { _ in true })
        router.appBecameReady { routed.append($0) }
        router.handle(URL(string: "myapp://profile/me")!)
        router.userDidLogOut()
        loggedIn = true
        router.userDidLogIn()
        XCTAssertTrue(routed.isEmpty)
    }
}
```

Manual:

```
xcrun simctl openurl booted "myapp://item/42"
xcrun simctl openurl booted "https://example.com/item/42"
```

Universal Links on device: long-press the link in Notes → it must offer
"Open in <App>"; if it opens Safari, AASA/entitlement is wrong.
