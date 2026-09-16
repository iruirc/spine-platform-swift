# di-factory — detailed guide

## Contents

- Installation
- Core Concepts
- Resolution: Property Wrappers
- Scopes
- Parameterized Factories
- AutoRegistering
- Modular Containers
- Contexts
- Coordinator and Module Assembly
- Testing
- Concurrency
- Swinject vs Factory
- Migration: Swinject → Factory
- Debugging Tips

## Installation

Swift Package Manager:

```swift
// Package.swift
.package(url: "https://github.com/hmlongco/Factory.git", from: "3.0.0")

// Targets
.product(name: "FactoryKit", package: "Factory"),               // app target
.product(name: "FactoryTesting", package: "Factory"),           // ONLY test target
```

```swift
import FactoryKit            // every file that names Container, Factory or a property wrapper
import FactoryTesting        // test files: the `.container` trait for Swift Testing
```

### Migrating from 2.x

- **Toolchain.** Factory 3 declares `swift-tools-version: 6.1` (Xcode 16.3 or later) and ships through Swift Package Manager only; a CocoaPods project stays on 2.5.3.
- **Module.** The `Factory` library is gone. Link `FactoryKit` and replace `import Factory` with `import FactoryKit`: 2.5 still built the old name, 3.0 fails with `no such module 'Factory'`.
- **Main-actor factories.** 2.x built them with `self { @MainActor in … }`. Factory 3 wants `@MainActor` on the factory variable and a plain closure, and rejects the 2.x closure on an unannotated variable — see Concurrency.
- **Circular-dependency check.** `manager.dependencyChainTestMax` became the `manager.circularDependencyTesting` flag.

## Core Concepts

### Container

Registrations live as **computed properties in extension Container**. Each such property returns a `Factory<T>` that knows how to resolve an instance. `Container` itself is a `final` class with `@TaskLocal static var shared`, so it cannot be subclassed; a separate namespace is a class of your own that adopts `SharedContainer` — see "Modular Containers" below.

```swift
import FactoryKit

extension Container {
    var userService: Factory<UserServiceProtocol> {
        self { UserService(networkClient: self.networkClient(), storage: self.keychainStorage()) }
    }

    var networkClient: Factory<HTTPClient> {
        self { URLSessionHTTPClient() }.singleton
    }

    var keychainStorage: Factory<KeychainStorage> {
        self { KeychainStorage(service: "com.example.app") }.singleton
    }
}
```

**What matters:**
- `self { … }` is syntactic sugar over `Factory(self) { … }`. Use the short form.
- The property name **becomes the registration key** (`StaticString = #function`). Don't rename it in production without a migration — old `register` overrides will be lost.
- The graph is wired **through the same `self`** inside the closure: `self.networkClient()`. NOT through `Container.shared.networkClient()` — otherwise isolation breaks when a separate `Container()` is created for tests or modules.

### Factory<T>

`Factory<T>` is a value type, not the instance itself. It's resolved via `callAsFunction`:

```swift
let service = Container.shared.userService()    // equivalent to .resolve()
```

Creating a `Factory` is cheap; the actual instance only appears on call.

### Composition Root

Factory **does not replace the Composition Root** — it implements it via a `Container`. CR logic (where the `Container` is created, what's registered in it, when bootstrap runs) lives in the `di-composition-root` skill.

```swift
// The app's own warm-up, in an app-target extension: Factory has no bootstrap()
extension Container {
    func bootstrap() {
        _ = database()          // eager work that does not belong in autoRegister()
    }
}

// SceneDelegate / @main App
@main
struct MyApp: App {
    init() {
        Container.shared.bootstrap()    // autoRegister() needs no call: the first resolve runs it
    }
    var body: some Scene { … }
}
```

**Never reach for `Container.shared` below the composition edge** — there, dependencies come through an explicit constructor. Otherwise you get a Service Locator (see "`Container.shared` from the domain layer — Service Locator" below).

### `Container.shared` from the domain layer — Service Locator

```swift
// ❌ Anti-pattern
final class ProfileService {
    func load() {
        let analytics = Container.shared.analytics()     // hidden dependency
    }
}

// ✅ Correct: explicit init
final class ProfileService {
    private let analytics: AnalyticsProtocol
    init(analytics: AnalyticsProtocol) { self.analytics = analytics }
}
```

Services, repositories, ViewModels and Coordinators accept dependencies through init. Property wrappers belong only to the composition edge that the skill's `Resolution` names.

### Resolving via `Container.shared` inside a Factory closure

```swift
// ❌ Breaks modular containers and tests
extension Container {
    var profileService: Factory<ProfileService> {
        self { ProfileService(api: Container.shared.apiClient()) }
    }
}

// ✅ Use self
extension Container {
    var profileService: Factory<ProfileService> {
        self { ProfileService(api: self.apiClient()) }
    }
}
```

If someone creates a separate `Container()` for tests, in the first variant `apiClient` will come from `.shared` — test isolation is broken.

## Resolution: Property Wrappers

Every wrapper resolves from `Container.shared`, so it sits only at the composition edge the skill's `Resolution` names; the owners below are those edges.

### `@Injected` — eager, sync

Resolved **at the moment the owner is created**. Use for required dependencies.

```swift
@main
struct MyApp: App {
    @Injected(\.analyticsService) private var analytics

    init() {
        analytics.track(.appLaunched)
    }

    var body: some Scene { … }
}
```

`\.analyticsService` is a KeyPath to the `Container.analyticsService` property.

### `@LazyInjected` — lazy, sync

Resolved on first access. Use when the dependency isn't always needed or the owner is created frequently.

```swift
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    @LazyInjected(\.biometricAuthenticator) private var biometric
    // BiometricAuthenticator is created only if the scene actually asks for biometrics
}
```

### `@WeakLazyInjected` — weak reference

Use to **break cycles** or for optionally-cached resources.

```swift
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    @WeakLazyInjected(\.imageCache) private var imageCache: ImageCache?
    // imageCache lives while someone else retains it
}
```

### `@InjectedObservable` — for @Observable view models

```swift
@MainActor
@Observable
final class ContentViewModel {
    private let repository: RepositoryProtocol
    init(repository: RepositoryProtocol) { self.repository = repository }
}

struct ContentView: View {          // the root view
    @InjectedObservable(\.contentViewModel) var viewModel
    var body: some View { … }
}
```

The registration builds the ViewModel through its initializer; the ViewModel never resolves.

### Direct resolution (no property wrappers)

When `@Injected` doesn't fit (`ParameterFactory`, non-object, manual assembly):

```swift
let service = Container.shared.userService()
let detail = Container.shared.detailViewModel(itemId)   // see ParameterFactory
```

### `@Injected` services in a SwiftUI `View`

```swift
// ❌ Service directly in the View — hidden dependency, the View can't be previewed with a mock without an AutoRegistering hack
struct ProfileView: View {
    @Injected(\.userService) var userService
    @Injected(\.analytics) var analytics
    var body: some View { … }
}

// ✅ The root view resolves the screen's ViewModel and passes it through init
struct RootView: View {
    var body: some View {
        NavigationStack {
            HomeView().navigationDestination(for: ProfileRoute.self) { _ in
                ProfileView(viewModel: Container.shared.profileViewModel())
            }
        }
    }
}

// ✅ Composable components — via init, no DI:
struct ProfileHeaderView: View {
    let user: User
    let onEdit: () -> Void
    var body: some View { … }
}
```

**Rule:**
- Services (`UserService`, `Analytics`, `Repository`) — **never** in a `View`. The ViewModel receives them through `init`, from its registration.
- `@InjectedObservable` and `Container.shared` — only in the root view; a screen's `View` takes its ViewModel through `init`.
- Composable subviews — `let`/`@Binding` via init. DI = a headache for previews and snapshot tests.

## Scopes

Scope is controlled by a modifier after `self { … }`. Default is `.unique` (a new instance on every resolve).

| Scope | Behavior | When to use |
|---|---|---|
| `.unique` (default) | New instance every time | ViewModels, Coordinators, stateful |
| `.singleton` | One global instance **per process** (not bound to the Container) | A single external resource (Keychain wrapper) |
| `.cached` | One instance **per this Container**, until `reset()` | Services (NetworkClient, Database) |
| `.shared` | Weak: alive while someone holds a strong reference; otherwise recreated | Optional shared caches |
| `.graph` | One instance **within a single top-level resolve** | Shared state inside a single feature's graph |

```swift
extension Container {
    var networkClient: Factory<HTTPClient> {
        self { URLSessionHTTPClient() }.cached         // singleton-within-this-Container
    }
    var keychainStorage: Factory<KeychainStorage> {
        self { KeychainStorage(service: "...") }.singleton  // process-global
    }
    var imageCache: Factory<ImageCache> {
        self { ImageCache() }.shared                   // weak
    }
    @MainActor
    var profileViewModel: Factory<ProfileViewModel> {
        self { ProfileViewModel(userService: self.userService()) }   // .unique by default
    }
}
```

**`.cached` vs `.singleton`:**
- `.cached` — the instance lives in `Container.shared` (or another `Container`), cleared via `reset()`. **This is what you usually want** for testability.
- `.singleton` — the instance **survives** `Container.reset()`: it lives in the global `Scope.singleton`, which only `Scope.singleton.reset()` clears. Use only for system resources whose destruction is dangerous (Keychain handle, OSLog subsystem).

**Time-to-live:** `self { … }.singleton.timeToLive(60 * 5)` — recreates the instance after N seconds. Useful for tokens / short-lived caches.

### `.singleton` for a ViewModel — shared state across screens

```swift
// ❌ All screens see the same state
extension Container {
    @MainActor
    var profileViewModel: Factory<ProfileViewModel> {
        self { ProfileViewModel(userService: self.userService()) }.singleton
    }
}

// ✅ ViewModel = .unique (default)
extension Container {
    @MainActor
    var profileViewModel: Factory<ProfileViewModel> {
        self { ProfileViewModel(userService: self.userService()) }
    }
}
```

## Parameterized Factories

When the instance requires a runtime parameter (screen id, flow config):

```swift
extension Container {
    @MainActor
    var detailViewModel: ParameterFactory<String, DetailViewModel> {
        self { itemId in
            DetailViewModel(itemId: itemId, service: self.itemService())
        }
    }
}

// Resolve
let vm = Container.shared.detailViewModel("item-123")
```

**Multiple parameters** — via tuple:

```swift
extension Container {
    @MainActor
    var chatViewModel: ParameterFactory<(String, String), ChatViewModel> {
        self { (roomId, userId) in
            ChatViewModel(roomId: roomId, userId: userId, chat: self.chatService())
        }
    }
}

let vm = Container.shared.chatViewModel(("room-1", "user-42"))
```

**Limitations:**
- `@Injected` does NOT work with `ParameterFactory` — there's no way to pass parameters before the wrapper is initialized. Use `Container.shared.foo(arg)` directly or pass the dependency explicitly through init.
- Caching (`.cached`/`.singleton`) by default **ignores parameters** — the same instance is returned for different ids. For key-by-parameters use `scopeOnParameters`.

### ParameterFactory vs factory function

`ParameterFactory` is the canonical path the author recommends. Use it **by default**: you get scopes (`.cached.scopeOnParameters`), contexts (`.onTest`/`.onPreview`), `register` overrides in tests, and a uniform style with the rest of your `var foo: Factory<...>`.

A plain factory function — only when **none of the above is needed** and you want named arguments:

```swift
// Acceptable ONLY when: no need for .cached/.shared, no .onTest override, no register-based mocks
extension Container {
    @MainActor
    func chatViewModel(roomId: String, userId: String) -> ChatViewModel {
        ChatViewModel(roomId: roomId, userId: userId, chat: self.chatService())
    }
}
```

| Criterion | `ParameterFactory` | Factory function |
|---|---|---|
| Scopes (`.cached`, `.singleton`) | ✅ via `scopeOnParameters` | ❌ always a new instance |
| Contexts (`.onTest`, `.onPreview`) | ✅ | ❌ |
| `register` override in tests | ✅ | ❌ — only by swapping the implementation |
| Named arguments | ❌ — tuple for 2+ | ✅ |
| Suited for | ViewModels with runtime ids, any prod case | One-liner factories with no lifecycle |

**Rule:** if there's at least one parameter and you need cache/context/mocks — `ParameterFactory`. Otherwise — choose by API aesthetics.

### ParameterFactory + `.cached` without `scopeOnParameters`

```swift
// ❌ Same instance for different itemIds
extension Container {
    @MainActor
    var detailViewModel: ParameterFactory<String, DetailViewModel> {
        self { DetailViewModel(itemId: $0) }.cached
    }
}

let vm1 = Container.shared.detailViewModel("a")
let vm2 = Container.shared.detailViewModel("b")
// vm1 === vm2, both look at itemId "a"

// ✅ Either .unique, or scopeOnParameters
self { DetailViewModel(itemId: $0) }.cached.scopeOnParameters
```

## AutoRegistering

If you need to run code **once before the first resolution** (register defaults, read config, hook up contexts):

```swift
extension Container: @retroactive AutoRegistering {
    public func autoRegister() {
        // Conditional defaults
        #if DEBUG
        analyticsService.register { NoOpAnalytics() }
        #endif

        // Context-bound overrides: while a context is active, it wins over `register`
        networkClient.onPreview { MockHTTPClient(scenario: .happy) }
        crashReporter.onTest { NoOpCrashReporter() }
    }
}
```

`@retroactive` silences the compiler's warning about conforming an imported type to an imported protocol. `autoRegister()` runs lazily before the first resolve on each `Container` instance, and again after every reset that drops registrations — `reset()` (whose default is `.all`) or `reset(options: .registration)`.

**Use it for:**
- Default overrides in DEBUG/Test/Preview
- Registering factory methods from sub-modules (see below)
- Configuration that depends on bundle / env

**Do NOT use it for:**
- Heavy initialization (DB, network) — that belongs in CR `bootstrap()`
- Business logic

### `register` in production code outside `autoRegister()` or tests

```swift
// ❌ Somewhere in SceneDelegate
Container.shared.networkClient.register { CustomClient() }

// Was called ONCE — but any subsequent reset() returns the original
```

Overrides should live either in `autoRegister()` (via context modifiers) or in tests. Otherwise you're fighting the reset lifecycle.

## Modular Containers

> **Rule first:** `import FactoryKit` **inside an SPM package is forbidden** — by the same rigid rule that applies to Swinject. This is required by `pkg-spm-design` (universal rule 1). A package always accepts its dependencies through `init(dependencies:)`. What's described below is **organization in the app target**, not in SPM packages.

The main modular pattern with Factory: one `Container.shared`, registrations split into files in the app target — one file per feature/layer:

```
App/
├── Composition/
│   ├── Container+Networking.swift      // apiClient, httpMiddleware
│   ├── Container+Persistence.swift     // database, repositories
│   ├── Container+Profile.swift         // profileService, profileViewModel
│   ├── Container+Settings.swift        // settingsService, settingsViewModel
│   └── Container+Bootstrap.swift       // AutoRegistering, context overrides
├── App.swift
└── ...
```

Each file is an `extension Container` with its own properties:

```swift
// App/Composition/Container+Profile.swift
import FactoryKit
import ProfileFeature       // SPM package — no Factory inside

extension Container {
    var profileService: Factory<ProfileServiceProtocol> {
        self { ProfileService(api: self.apiClient()) }.cached
    }
    var profileModule: Factory<ProfileModule> {
        self { ProfileModule(dependencies: .init(
            api: self.apiClient(),
            logger: self.logger()
        )) }
    }
}
```

```swift
// App/Composition/Container+Networking.swift
import FactoryKit

extension Container {
    var apiClient: Factory<APIClient> {
        self { URLSessionAPIClient(config: .production) }.cached
    }
}
```

`Container.shared.profileModule()` works in the host app, in previews, and in tests. The `ProfileFeature` SPM package contains zero lines about Factory — it accepts its dependencies via `init(dependencies: ProfileFeatureDependencies)`.

**Downside:** all extensions share one `Container` namespace. A name collision is undefined behavior (one property silently overrides another, because the key is the property name). Solution: feature prefixes (`profileService`, `profileViewModel`) or your own `SharedContainer` (see below).

### Custom `SharedContainer` (for very large apps)

When the monorepo grows to dozens of features and the name-collision risk is real:

```swift
// App/Composition/ProfileContainer.swift
public final class ProfileContainer: SharedContainer {
    @TaskLocal public static var shared = ProfileContainer()
    public let manager = ContainerManager()
    public init() {}
}

extension ProfileContainer {
    var service: Factory<ProfileServiceProtocol> {
        self { ProfileService() }.cached
    }
}
```

```swift
// Usage
let svc = ProfileContainer.shared.service()
// or with a property wrapper:
@Injected(\ProfileContainer.service) var service
```

`@Injected(\KeyPath)` supports any `SharedContainer`, not just the base `Container`. This file also lives **in the app target**, not in a package.

`@TaskLocal` on `shared` is what lets a test swap in a fresh container. The `.container` trait scopes only `Container`, so the test target declares a trait for `ProfileContainer`; a `static let shared` has no `$shared` to scope, and parallel tests share one instance:

```swift
extension Trait where Self == ContainerTrait<ProfileContainer> {
    static var profileContainer: ContainerTrait<ProfileContainer> {
        .init(shared: ProfileContainer.$shared, container: .init())
    }
}

@Suite(.container, .profileContainer)
struct ProfileFeatureTests { … }
```

### When to pick which

| Situation | Pick |
|---|---|
| One team, < 30 features | `extension Container` with prefixes in a single namespace |
| Multiple teams / 30+ features / real risk of name collisions | A custom `SharedContainer` per feature group |
| SPM package (any archetype) | Never Factory inside. `init(dependencies:)` + registration in the app target |

See also `pkg-spm-design`'s **library/feature archetypes** section — it describes the general contract for how a package accepts dependencies through `init`, which works with any DI framework (Swinject / Factory / manual).

### Name collisions across registration files

Two registration files in the app target declare `extension Container { var apiClient: Factory<…> }` with different implementations → one silently overrides the other. Grep for `var .*: Factory<` across the app target, or give each feature group its own `SharedContainer`.

## Contexts

Factory can override registrations **based on the launch context** without modifying production code:

```swift
extension Container: @retroactive AutoRegistering {
    public func autoRegister() {
        analyticsService
            .onTest { NoOpAnalytics() }
            .onPreview { LoggingAnalytics() }
            .onDebug { VerboseAnalytics() }
            .onSimulator { SimulatorOnlyAnalytics() }

        // Launch argument: mockMode
        networkClient.onArg("mockMode") { MockHTTPClient() }
    }
}
```

| Modifier | When it triggers |
|---|---|
| `.onTest { … }` | XCTest / Swift Testing process |
| `.onPreview { … }` | SwiftUI Preview (`XCODE_RUNNING_FOR_PREVIEWS == 1`) |
| `.onDebug { … }` | DEBUG build, tests and previews included |
| `.onSimulator { … }` | iOS Simulator |
| `.onDevice { … }` | Real device |
| `.onArg("name") { … }` | A launch argument equal to `name` — the whole argv element, so `-name 1` does not match |

Contexts are **additive** — several can be chained. When more than one applies, Factory takes the first of arg, preview, test, simulator, device, debug; then a `register` override; then the production closure (the one inside `self { … }`). An active context therefore wins over `register`: a test cannot register over a factory that has `.onTest` or `.onDebug`, nor a preview over one that has `.onPreview`. The preview, test and debug contexts take effect only in DEBUG builds.

## Coordinator and Module Assembly

The architectural pattern (`AppDependencies` → `*FeatureDependencies` → `CoordinatorFactory` → `ModuleFactory` → `Assembly`) **doesn't change** — only the `AppDependencyContainer` implementation does. See `di-module-assembly` for the full example. The difference vs Swinject:

```swift
// Swinject
@MainActor
final class AppDependencyContainer: AppDependencies {
    private let container: Container
    var userService: UserServiceProtocol { container.resolve(UserServiceProtocol.self)! }
}

// Factory
@MainActor
final class AppDependencyContainer: AppDependencies {
    var userService: UserServiceProtocol { Container.shared.userService() }
    var analyticsService: AnalyticsServiceProtocol { Container.shared.analyticsService() }
    // …
}
```

`import FactoryKit` lives **only** in `AppDependencyContainer` (and the `extension Container` files that register services). `ModuleFactoryImp`, `CoordinatorFactoryImp`, feature `*Factory`/`*Assembly`, Coordinators, ViewModels and Views must not import `FactoryKit` and must not touch `Container` / `Container.shared`. They receive `AppDependencies` / `*FeatureDependencies` and feature factory protocols through init.

```swift
// ✅ Correct — ModuleFactoryImp receives AppDependencies, NOT Container
@MainActor
final class ModuleFactoryImp: ProfileModuleFactory {
    private let dependencies: AppDependencies
    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func makeProfileModule() -> ModuleComponents<ProfileViewController, ProfileViewModel> {
        ProfileAssembly.assemble(dependencies: dependencies)    // protocol upcast: AppDependencies → ProfileFeatureDependencies
    }
}
```

```swift
// ❌ Wrong — ModuleFactoryImp imports FactoryKit and reaches into Container.shared
import FactoryKit                                              // ← never here

@MainActor
final class ModuleFactoryImp: ProfileModuleFactory {
    func makeProfileModule() -> ModuleComponents<ProfileViewController, ProfileViewModel> {
        ProfileAssembly.assemble(
            dependencies: Container.shared                     // ← Service Locator
        )
    }
}
```

```swift
// ❌ Wrong — Coordinator accepts the container instead of the factory
final class AppCoordinator {
    init(window: UIWindow, container: Container) { … }         // ← never accept Container/Resolver
}
```

> **Shortcut inside ModuleFactory.** It can be tempting to let `ModuleFactory` call `Container.shared.foo()` directly and drop the `AppDependencyContainer` facade. Don't do this: it disguises a Service Locator, breaks Coordinator tests (no init injection — no mock), and zeroes out compile-time visibility of the dependency surface. The pattern is the same on 1, 5, and 50 screens — the cost of the facade pays for itself the first time you have a regression.

> **Without the chain.** A feature with no ModuleFactory layer still keeps `@Injected` off its ViewModels and Coordinators: the root view or the `@main` App resolves, and everything below it takes `init` parameters. Mixing both styles in one feature produces hidden dependencies that show up in no initializer.

## Testing

### Unit Tests — Direct Injection (preferred)

As with Swinject — for ViewModels, a direct `init(...)` with mocks is best:

<!-- typecheck -->
```swift
import XCTest

@MainActor
final class ProfileViewModelTests: XCTestCase {
    func test_load_success() async {
        let mock = MockUserService(result: .success(.fixture))
        let sut = ProfileViewModel(userService: mock)

        await sut.load()

        XCTAssertEqual(sut.state, .loaded(.fixture))
    }
}
```

ViewModels take their dependencies through init, so this is the default; the test class is `@MainActor` because the ViewModel is. To test the registered graph — see below.

### Override via `register` — the registered graph

```swift
@MainActor
final class ProfileViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Container.shared.reset()        // otherwise a previous test's override leaks in
        Scope.singleton.reset()         // a container reset leaves singletons cached
    }

    func test_load_success() async {
        Container.shared.userService.register {
            MockUserService(result: .success(.fixture))
        }

        let sut = Container.shared.profileViewModel()    // the registration passes the mock to init

        await sut.load()
        XCTAssertEqual(sut.state, .loaded(.fixture))
    }
}
```

### Swift Testing — `.container` trait

`FactoryTesting` provides a Suite trait that automatically scopes a Container per test. No manual `reset()` calls are needed:

```swift
import Testing
import FactoryKit
import FactoryTesting
@testable import App

@MainActor
@Suite(.container)
struct ProfileViewModelTests {

    @Test func loadSuccess() async {
        Container.shared.userService.register {
            MockUserService(result: .success(.fixture))
        }
        let sut = Container.shared.profileViewModel()
        await sut.load()
        #expect(sut.state == .loaded(.fixture))
    }

    @Test func loadFailure() async {
        Container.shared.userService.register {
            MockUserService(result: .failure(TestError.network))
        }
        let sut = Container.shared.profileViewModel()
        await sut.load()
        #expect(sut.state == .error)
    }
}
```

Each `@Test` gets a fresh `Container.shared` and its own copy of `Scope.singleton`, both through `@TaskLocal`, so a registration or a singleton one test creates never reaches another. Tests can run **in parallel** without interference — that's the main argument for moving Factory projects to Swift Testing. A custom `SharedContainer` needs a trait of its own — see Modular Containers.

### Reset gotchas

`Container.shared.reset()` takes `options: .all` by default.

| Scenario | Behavior |
|---|---|
| `.unique` | No caches — `reset()` doesn't affect anything |
| `.cached`, `.shared` | Cleared by `Container.shared.reset()` |
| `.singleton` | Survives every container reset: the cache is the global `Scope.singleton`. Clear it with `Scope.singleton.reset()`, or one factory with `Container.shared.foo.reset()` |
| Override via `register` | Cleared by `Container.shared.reset()` |
| Contexts set in `autoRegister()` | Cleared, then set again: `autoRegister()` runs on the next resolve |

**Rule:** in XCTest `setUp` call `Container.shared.reset()`, and `Scope.singleton.reset()` when the graph holds singletons. Otherwise test leaks are guaranteed. `@Suite(.container)` needs neither.

### Preview overrides

**Centralized** — `.onPreview` inside `autoRegister()` for the dependencies no preview varies. One source of truth for all `#Preview`s, doesn't pollute the View files themselves:

```swift
extension Container: @retroactive AutoRegistering {
    public func autoRegister() {
        analytics.onPreview { NoOpAnalytics() }
        imageLoader.onPreview { PlaceholderImageLoader() }
    }
}
```

**Local override** — the factory's `.preview` modifier, for the dependency a `#Preview` is about. It registers the mock and returns an `EmptyView`, so the body stays a view builder and needs no `return`:

```swift
#Preview {
    Container.shared.userService.preview { MockUserService(result: .success(.fixture)) }
    ProfileView(viewModel: Container.shared.profileViewModel())
}

#Preview("Loading state") {
    Container.shared.userService.preview { MockUserService(result: .pending) }
    ProfileView(viewModel: Container.shared.profileViewModel())
}
```

Keep the two apart: while `.onPreview` is active it wins over any registration, so a factory that has `.onPreview` ignores `.preview`. Several registrations at once go through `Container.preview { $0.userService.register { … } }`.

### Forgot `reset()` in setUp

```swift
// ❌ Tests influence each other
final class Tests: XCTestCase {
    func test_a() {
        Container.shared.foo.register { MockA() }
        // …
    }
    func test_b() {
        // MockA from test_a is still active → test_b is unpredictable
    }
}

// ✅ ALWAYS reset
final class Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        Container.shared.reset()
    }
}
```

Better — Swift Testing with `@Suite(.container)`, then no reset is needed.

## Concurrency

`Container` is `Sendable`. Registration and resolve are thread-safe (internal lock). But **the instance you return** must be Sendable / properly isolated — Factory does not perform magic.

### `@MainActor` view models

A main-actor type is registered by a `@MainActor` factory variable; the closure inside needs no annotation of its own:

```swift
@MainActor
@Observable
final class ContentViewModel {
    private let repository: RepositoryProtocol
    init(repository: RepositoryProtocol) { self.repository = repository }
}

extension Container {
    @MainActor
    var contentViewModel: Factory<ContentViewModel> {
        self { ContentViewModel(repository: self.repository()) }
    }
}
```

Without `@MainActor` on the variable the registration does not compile in any mode of `concurrency-architecture` → "Toolchain modes": the plain closure calls a main actor-isolated initializer from a nonisolated context, and 2.x's `self { @MainActor in … }` loses its global actor when Factory 3 stores it. Default main-actor isolation does not help: `Container` is declared `nonisolated`, and so are the members of its extensions.

Only main-actor code can resolve such a factory — the `@main` App, the scene delegate, the root view, `AppDependencyContainer` — and that composition edge is the only place that resolves at all. Work that runs off the main actor (a detached task, a `BGTaskScheduler` handler, a background `URLSession` delegate) never reaches into `Container.shared`: the edge resolves the nonisolated services it needs and passes them in through `init`.

### `@Injected` in an `@Observable` ViewModel

```swift
// ❌ Hidden dependency — and without @ObservationIgnored every resolve triggers a UI update
@MainActor
@Observable
final class FeatureViewModel {
    @Injected(\.repository) private var repository
}

// ✅ Dependency through init; the registration passes it
@MainActor
@Observable
final class FeatureViewModel {
    private let repository: RepositoryProtocol
    init(repository: RepositoryProtocol) { self.repository = repository }
}
```

Code that keeps `@Injected` inside an `@Observable` class while it migrates marks it `@ObservationIgnored`.

### `nonisolated` Factory from a global-actor context

If the registration is pure (no UI), keep it nonisolated — otherwise the whole feature ends up on MainActor:

```swift
extension Container {
    var repository: Factory<RepositoryProtocol> {
        self { Repository(client: self.apiClient()) }.cached     // nonisolated → OK
    }
}
```

## Swinject vs Factory

| Aspect | Swinject | Factory |
|---|---|---|
| Registration | `container.register(Foo.self) { _ in Foo() }` — runtime, in an Assembly | `extension Container { var foo: Factory<Foo> { self { Foo() } } }` — compile-time property |
| Type-safety | Runtime: missing registration → `resolve(...)!` crash | Compile-time: factory missing → code doesn't compile |
| Binding | By type + optional `name: String` | By KeyPath to a `Container` property |
| Resolve in code | `container.resolve(Foo.self)!` or hand-written wrappers | `Container.shared.foo()` or `@Injected(\.foo)` |
| Property wrappers | None built-in (you'd write your own) | First-class: `@Injected`, `@LazyInjected`, `@WeakLazyInjected`, `@InjectedObservable` |
| SwiftUI / Observation | Manual integration (`StateObject`, EnvironmentObject) | `@InjectedObservable` + `@ObservationIgnored` out of the box |
| Scopes | `.transient`, `.container`, `.weak`, `.graph`, custom | `.unique`, `.cached`, `.singleton`, `.shared`, `.graph`, `.timeToLive`, `.scopeOnParameters` |
| Parameters in factory | `register { (_, arg: String) in … }`, up to 9 args | `ParameterFactory<P, T>`, for 2+ — tuple |
| Contexts (test/preview/debug) | None — assemble your own via `#if DEBUG` + flags | `.onTest` / `.onPreview` / `.onDebug` / `.onSimulator` / `.onArg` |
| Bootstrap hook | Configure Assembly + assembler in the CR | `AutoRegistering.autoRegister()` lazily on first resolve |
| Modular setup | `Assembly` per module + `assembler.apply([...])` | `extension Container` per file, optionally a custom `SharedContainer` |
| SPM package | DI framework **forbidden** in main target → `init(dependencies:)` | Same restriction → `init(dependencies:)` |
| Test isolation | Fresh `Container()` per test OR manual Assembly reset | `Container.shared.reset()` plus `Scope.singleton.reset()` OR `@Suite(.container)` (FactoryTesting) for parallel Swift Testing |
| Mock overrides | `container.register(Foo.self) { _ in Mock() }` (on top) | `Container.shared.foo.register { Mock() }` |
| Performance | Dictionary lookup by type, argument types and name | Dictionary lookup by type and property name under a global recursive lock, on every resolve |
| Async / Sendable | Not Sendable out of the box, manual synchronization | Container is Sendable, register/resolve thread-safe |
| Maturity | Older, more boilerplate, native to the UIKit era | Newer, tailored for SwiftUI/Observation/Swift 6 |

**When to pick which:**

- **Greenfield SwiftUI** + iOS 16+ + `@Observable` → **Factory**
- **Existing Swinject** in production → don't migrate for the sake of migration; see Migration below only if there's specific pain (tests, Swift 6, SwiftUI integration)
- Need **named registrations of the same type** (`name: "primary" / "fallback"`) or autoregister plugins → Swinject
- Need contexts (preview/test/debug overrides) **without your own scaffolding** → Factory
- Team coming from Spring/Dagger → Swinject is mentally closer (Assembly = Module)

## Migration: Swinject → Factory

| Swinject | Factory |
|---|---|
| `container.register(Foo.self) { _ in Foo() }` | `extension Container { var foo: Factory<Foo> { self { Foo() } } }` |
| `.inObjectScope(.container)` | `.cached` |
| `.inObjectScope(.transient)` | `.unique` (Factory's default) |
| `.inObjectScope(.weak)` | `.shared` |
| `.inObjectScope(.graph)` (Swinject's default) | `.graph` |
| `container.resolve(Foo.self)!` | `Container.shared.foo()` |
| `r.resolve(Foo.self, name: "x")` | A custom key via KeyPath or a separate `var fooX: Factory<Foo>` |
| `Assembly.assemble(container:)` | `extension Container` per feature + `AutoRegistering` |
| `register(Foo.self) { (_, arg: String) in … }` | `var foo: ParameterFactory<String, Foo>` |

**Migration strategy:**
1. Rewrite services and registrations feature by feature (Container extension next to the old Assembly).
2. Leave Coordinators alone — they work through `AppDependencyContainer` (see `di-module-assembly`); only the facade implementation changes.
3. Don't keep a mixed state (some Swinject + some Factory) longer than one sprint — two DI frameworks at once = double the test complexity.

## Debugging Tips

Factory keeps its registration table internal, so there is no list of keys to print. Trace the resolutions instead, or decorate them:

```swift
// Trace every resolution cycle as a dependency tree (DEBUG builds, all containers)
#if DEBUG
Container.shared.manager.trace = true
#endif

// Decorator — sees every instance this container resolves
Container.shared.decorator { resolved in
    print("Resolved: \(type(of: resolved))")
}
```

The decorator is invoked on EVERY resolve, cached instances included — keep it out of release builds; `decorator(nil)` removes it. A single factory takes a `.decorator { … }` modifier of its own.
