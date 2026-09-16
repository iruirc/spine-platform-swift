# di-swinject — detailed guide

## Contents

- Core Concepts
- Object Scopes
- Registration Patterns
- Assembly Pattern
- @MainActor UI types + Swinject
- Testing Configuration
- Debugging Tips
- Swinject vs Factory

## Core Concepts

### Container Setup

The Swinject `Container` is created in the Composition Root and wrapped in an `AppDependencyContainer` facade — never used as a global `static let shared`. **Details on CR — in the `di-composition-root` skill.**

Minimum for context:

```swift
import Swinject
import SwinjectAutoregistration

@MainActor
final class AppDependencyContainer {
    private let container = Container()

    func bootstrap() {
        registerServices()
    }
}
```

> **`static let shared` is forbidden** — it turns the container into a Service Locator (hidden dependencies, no testability). See the `di-composition-root` skill for the correct location and lifetime of the container.

### Basic Registration

```swift
// Register with explicit factory
container.register(UserServiceProtocol.self) { _ in
    UserService()
}

// Register with dependencies
container.register(ProfileRepositoryProtocol.self) { r in
    ProfileRepository(
        apiClient: r.resolve(APIClientProtocol.self)!,
        cache: r.resolve(CacheProtocol.self)!
    )
}
```

### Auto-registration

Using `SwinjectAutoregistration` for cleaner syntax:

```swift
// Auto-resolve dependencies
container.autoregister(ProfileRepository.self, initializer: ProfileRepository.init)

// With protocol
container.autoregister(
    ProfileRepositoryProtocol.self,
    initializer: ProfileRepository.init
)
```

## Object Scopes

### `.transient`

New instance every time. Use for stateful objects.

```swift
container.register(FormDraft.self) { r in
    FormDraft(validator: r.resolve(ValidatorProtocol.self)!)
}
// Each resolve() creates new instance
```

**Use for**:
- Stateful helpers each consumer needs fresh (a form draft, an upload session)

ViewModels and Coordinators are not registered: a `@MainActor` `*Assembly` builds them (see `@MainActor UI types + Swinject`).

### `.container` (Singleton)

Single instance for container lifetime. Use for stateless services.

```swift
container.register(NetworkServiceProtocol.self) { _ in
    NetworkService()
}.inObjectScope(.container)
// Same instance returned every time
```

**Use for**:
- Network clients
- Database managers
- Analytics services
- App settings
- Caches

### `.weak`

Shared while retained, recreated when released.

```swift
container.register(CacheProtocol.self) { _ in
    ImageCache()
}.inObjectScope(.weak)
// Shared if someone holds reference, otherwise recreated
```

**Use for**:
- Optional shared caches
- Resources that can be recreated
- Memory-sensitive singletons

### `.graph` (Default)

Same instance within single resolution graph, new for each top-level resolve. A `Container()` gives it to every registration without `inObjectScope`, `autoregister` included.

```swift
container.autoregister(SharedState.self, initializer: SharedState.init)
    .inObjectScope(.graph)

// If A and B both depend on SharedState:
// resolve(A.self) and resolve(B.self) → different SharedState
// But A and B resolved together share same SharedState
```

**Use for**:
- Shared state within a feature but not globally
- Request-scoped objects

### Wrong Scope Selection

```swift
// Form draft as singleton - shares state between consumers!
container.register(FormDraft.self) { ... }
    .inObjectScope(.container)

// Form draft as transient - fresh state each time
container.register(FormDraft.self) { ... }
    .inObjectScope(.transient)  // without it the scope is .graph
```

## Registration Patterns

### Protocol-Based Registration

Always register protocols, not concrete types:

```swift
// Correct
container.register(UserServiceProtocol.self) { _ in
    UserService()
}

// Avoid
container.register(UserService.self) { _ in
    UserService()
}
```

### Named Registrations

When multiple implementations of same protocol exist:

```swift
container.register(APIClientProtocol.self, name: "production") { _ in
    ProductionAPIClient()
}

container.register(APIClientProtocol.self, name: "staging") { _ in
    StagingAPIClient()
}

// Resolve by name
let client = container.resolve(APIClientProtocol.self, name: "production")!
```

### Registrations with Arguments

When instance needs runtime parameters:

```swift
container.register(UploadSession.self) { (r, uploadId: String) in
    UploadSession(
        uploadId: uploadId,
        client: r.resolve(APIClientProtocol.self)!
    )
}

// Resolve with argument
let session = container.resolve(UploadSession.self, argument: "upload-123")!
```

### Multiple Arguments

```swift
container.register(ChatConnection.self) { (r, roomId: String, userId: String) in
    ChatConnection(
        roomId: roomId,
        userId: userId,
        chatService: r.resolve(ChatServiceProtocol.self)!
    )
}

// Resolve
let connection = container.resolve(
    ChatConnection.self,
    arguments: "room-1", "user-42"
)!
```

### Circular Dependencies

A needs B and B needs A. If each factory resolves the other — through an initializer, or by setting a property before it returns — resolving either recurses until Swinject traps: "Infinite recursive call for circular dependency has been detected".

```swift
container.register(A.self) { r in A(b: r.resolve(B.self)!) }
container.register(B.self) { r in B(a: r.resolve(A.self)!) }
```

Break the cycle on one side. `AnalyticsService` is built without its user service and receives it through a `weak` property in `initCompleted`. Swinject calls `initCompleted` after it stores the new instance, so the resolve inside finds that `AnalyticsService` instead of building another:

```swift
container.register(UserServiceProtocol.self) { r in
    UserService(analytics: r.resolve(AnalyticsServiceProtocol.self)!)
}.inObjectScope(.container)

container.register(AnalyticsServiceProtocol.self) { _ in AnalyticsService() }
    .inObjectScope(.container)
    .initCompleted { r, analytics in
        (analytics as! AnalyticsService).userService = r.resolve(UserServiceProtocol.self)
    }
```

- Both sides are `.container`. `.transient` keeps no instance, so the cycle traps again; `.graph` keeps it for one resolve only, so the `weak` back reference can be `nil` afterwards.
- Resolving `UserService` first runs its factory twice and keeps one instance: keep that factory free of side effects.
- A cycle usually hides a third type both sides need; extracting it removes the cycle.

### Resolving in Initializers

```swift
// Accessing container during init — hidden dependency
class BadService {
    let dependency = appContainer.resolve(Dep.self)!
}

// Inject through initializer — explicit, testable
class GoodService {
    let dependency: DepProtocol
    init(dependency: DepProtocol) {
        self.dependency = dependency
    }
}
```

## Assembly Pattern

Organize registrations by feature using Assemblies:

```swift
class ServicesAssembly: Assembly {
    func assemble(container: Container) {
        container.register(NetworkServiceProtocol.self) { _ in
            NetworkService()
        }.inObjectScope(.container)

        container.register(DatabaseServiceProtocol.self) { _ in
            DatabaseService()
        }.inObjectScope(.container)
    }
}

class ProfileServicesAssembly: Assembly {
    func assemble(container: Container) {
        container.autoregister(
            ProfileRepositoryProtocol.self,
            initializer: ProfileRepository.init
        )
    }
}

// In DIContainer
let assembler = Assembler([
    ServicesAssembly(),
    ProfileServicesAssembly(),
    SettingsServicesAssembly(),
    // ... more assemblies
])
let container = assembler.resolver
```

A Swinject `Assembly` registers services. It is not the module's `*Assembly` enum, which builds the UI and never sees the container.

## @MainActor UI types + Swinject

Swinject's `Container.register(_:factory:)` takes a **nonisolated** `(Resolver) -> Service` closure. Calling a `@MainActor`-isolated initializer (any `UIViewController`/`NSViewController` subclass on iOS 13+/macOS, or any `@MainActor` ViewModel) from inside that closure is a Swift 6 error:

```
error: call to main actor-isolated initializer 'init(...)' in a synchronous nonisolated context
```

### ❌ Wrong — direct registration of `@MainActor` types

```swift
final class RootAssembly: Assembly {
    func assemble(container: Container) {
        // FAILS under Swift 6 — RootViewModel is @MainActor, closure is nonisolated.
        container.register(RootViewModel.self) { resolver in
            RootViewModel(appInfo: resolver.resolve(AppInfoService.self)!)
        }
        // FAILS — UIViewController.init is @MainActor-isolated by SDK annotation.
        container.register(RootViewController.self) { resolver in
            RootViewController(viewModel: resolver.resolve(RootViewModel.self)!)
        }
    }
}
```

### ❌ Also wrong — `MainActor.assumeIsolated`

```swift
container.register(RootViewModel.self) { resolver in
    MainActor.assumeIsolated {              // ← masks the design issue
        RootViewModel(appInfo: resolver.resolve(AppInfoService.self)!)
    }
}
```

`assumeIsolated` traps at runtime if the closure ever runs off the main actor — and the design intent ("UI is built on main") is hidden from the type system. Keep `assumeIsolated` for true legacy/sync-callback bridges, not for DI wiring you control.

### ❌ Also wrong — `*Factory` that holds a `Resolver`

```swift
// Modules/Root/RootFactory.swift
struct RootFactory {
    private let resolver: Resolver                              // ← Swinject leaks into feature code
    init(resolver: Resolver) { self.resolver = resolver }

    @MainActor
    func makeViewController() -> RootViewController {
        let viewModel = RootViewModel(appInfo: resolver.resolve(AppInfoService.self)!)
        return RootViewController(viewModel: viewModel)
    }
}
```

This solves the `@MainActor` build error but reintroduces the **Service Locator** anti-pattern that `di-module-assembly` exists to prevent: the Factory now imports `Swinject`, the dependency surface of the screen is invisible at the type level, and the closure can resolve anything from the global graph. Coordinator tests can no longer mock the Factory without spinning up a real container.

### ✅ Correct — `*Assembly` builds the UI on main from a `*FeatureDependencies` protocol

Use the canonical chain from `di-module-assembly`: `AppDependencyContainer` is the only type that imports `Swinject` and calls `container.resolve(...)`. The module's `*Assembly` receives a narrow `*FeatureDependencies` protocol and builds the View + ViewModel in a `@MainActor` `assemble` method:

```swift
// DI/Protocols/RootFeatureDependencies.swift
@MainActor
protocol RootFeatureDependencies {
    var appInfoService: AppInfoService { get }
}

// Modules/Root/RootAssembly.swift             ← no `import Swinject`
enum RootAssembly {
    @MainActor
    static func assemble(
        dependencies: RootFeatureDependencies
    ) -> ModuleComponents<RootViewController, RootViewModel> {
        let viewModel = RootViewModel(appInfo: dependencies.appInfoService)
        let view = RootViewController(viewModel: viewModel)
        return ModuleComponents(view: view, viewModel: viewModel)
    }
}

// DI/AppDependencyContainer.swift             ← the ONLY file that imports Swinject
import Swinject

@MainActor
final class AppDependencyContainer: AppDependencies {
    private let container: Container
    init(container: Container) { self.container = container }

    // RootFeatureDependencies conformance
    var appInfoService: AppInfoService {
        container.resolve(AppInfoService.self)!
    }
}

// DI/ModuleFactory/ModuleFactoryImp.swift     ← no `import Swinject`
@MainActor
final class ModuleFactoryImp: RootModuleFactory {
    private let dependencies: AppDependencies
    init(dependencies: AppDependencies) { self.dependencies = dependencies }

    func makeRootModule() -> ModuleComponents<RootViewController, RootViewModel> {
        // protocol upcast: AppDependencies → RootFeatureDependencies
        RootAssembly.assemble(dependencies: dependencies)
    }
}

// Coordinators/AppCoordinator.swift           ← receives ModuleFactory, NOT Resolver
@MainActor
final class AppCoordinator {
    private let moduleFactory: RootModuleFactory
    init(moduleFactory: RootModuleFactory) { self.moduleFactory = moduleFactory }

    func start(window: UIWindow) {
        window.rootViewController = moduleFactory.makeRootModule().view
        window.makeKeyAndVisible()
    }
}
```

**Rules:**

- Swinject registers services only; they are nonisolated and `Sendable`, or actors. ViewModels, Views and ViewControllers never go into the container.
- `*Assembly` is an `enum` with a `@MainActor` `assemble(dependencies:)`. It knows only its `*FeatureDependencies` protocol, never imports `Swinject` and never holds a `Resolver`.
- `ModuleFactoryImp` calls the Assembly. On UIKit and AppKit a Coordinator (or `AppDelegate`) calls the `ModuleFactory` on main; on SwiftUI the view that owns the root `NavigationStack` calls it inside `navigationDestination` (`di-module-assembly` → "Navigation End By UI Framework").
- `import Swinject` is restricted to `AppDependencyContainer` and the Swinject Assemblies that register services in it.
- Runtime parameters (`itemId`, `userId`, …) are parameters of `assemble` and of `make…Module`, not Swinject `arguments:` — keeps the isolation boundary explicit.

This is the chain `di-module-assembly` → "Canonical Chain" owns. The Swinject-specific part: the container holds only nonisolated services, and `Resolver` never appears outside `AppDependencyContainer`.

### Container as Service Locator

```swift
// Anti-pattern: passing container to Coordinator/ViewModel
class FeatureCoordinator {
    private let container: Resolver
    func start() {
        let vm = container.resolve(FeatureViewModel.self)!  // Hidden dependency
    }
}

// Correct: use Factory pattern (see di-module-assembly skill)
class FeatureCoordinator {
    init(router: Router,
         coordinatorFactory: CoordinatorFactory,
         factory: FeatureModuleFactory) {
        let module = factory.makeFeatureModule()  // Explicit, testable
    }
}
```

## Testing Configuration

### Unit Tests — Direct Injection (Preferred)

For ViewModels and services, inject mock dependencies directly — no container needed:

```swift
class ProfileViewModelTests: XCTestCase {
    func test_loadProfile_success() {
        let mockService = MockUserService(result: .success(testUser))
        let viewModel = ProfileViewModel(userService: mockService)

        viewModel.loadProfile()

        XCTAssertEqual(viewModel.state, .loaded(testUser))
    }

    func test_loadProfile_failure() {
        let mockService = MockUserService(result: .failure(TestError.network))
        let viewModel = ProfileViewModel(userService: mockService)

        viewModel.loadProfile()

        XCTAssertEqual(viewModel.state, .error("Network error"))
    }
}
```

### Integration Tests — Test Container

When testing the DI graph itself or integration between components, apply the production Assembly under test and register mocks for what it depends on:

```swift
class TestDIContainer {
    static func makeContainer() -> Container {
        let container = Container()
        ProfileServicesAssembly().assemble(container: container)

        container.register(APIClientProtocol.self) { _ in
            MockAPIClient()
        }

        container.register(CacheProtocol.self) { _ in
            InMemoryCache()
        }

        return container
    }
}
```

### Override Specific Dependencies

A later `register` of the same type and name replaces the earlier one. The test resolves a service: the container holds no ViewModels.

```swift
func testWithCustomMock() {
    let container = TestDIContainer.makeContainer()

    container.register(APIClientProtocol.self) { _ in
        MockAPIClient(shouldFail: true)
    }

    let repository = container.resolve(ProfileRepositoryProtocol.self)!
    // Test error handling path
}
```

## Debugging Tips

### Check Registration

`hasAnyRegistration(of:)` checks a registration without running its factory. Pass each type through a generic function: in the Swift 5 language mode, neither it nor `resolve` accepts an `Any.Type`.

```swift
#if DEBUG
func validateRegistrations(in container: Container) {
    func require<Service>(_ type: Service.Type) {
        if !container.hasAnyRegistration(of: type) {
            print("Missing registration: \(type)")
        }
    }

    require(NetworkServiceProtocol.self)
    require(DatabaseServiceProtocol.self)
    require(ProfileRepositoryProtocol.self)
}
#endif
```

### Log Resolutions

```swift
extension Container {
    func resolveWithLogging<T>(_ type: T.Type) -> T? {
        let result = resolve(type)
        #if DEBUG
        if result == nil {
            print("Failed to resolve: \(type)")
        } else {
            print("Resolved: \(type)")
        }
        #endif
        return result
    }
}
```

### Force Unwrapping Without Registration

```swift
// Crashes if not registered
let service = container.resolve(ServiceProtocol.self)!

// Defensive approach
guard let service = container.resolve(ServiceProtocol.self) else {
    fatalError("ServiceProtocol not registered")
}
```

## Swinject vs Factory

Swinject and Factory (see `di-factory`) solve the same problem in different ways. The choice:

| Criterion | Swinject | Factory |
|---|---|---|
| Compile-time safety | ❌ Resolve crash at runtime | ✅ Won't compile without a factory |
| Injection style | Constructor via `r.resolve(...)` | Property wrapper `@Injected` or `Container.shared.foo()` |
| Registrations | `register` / `autoregister` inside an Assembly | Computed property `var foo: Factory<Foo> { self { Foo() } }` |
| Runtime parameters | `register { (r, arg) in ... }` + `resolve(_:argument:)` | `ParameterFactory` (one parameter type per key) |
| Multiple impls of one type | `name:` parameter | Separate computed properties or modular containers |
| Autoregister (auto-resolve init args) | ✅ Via `SwinjectAutoregistration` | ❌ No (deps must be wired explicitly in the closure) |
| Inside an SPM package | ❌ Forbidden | ❌ Forbidden in the main target. Modular `extension Container` per feature — in the app target |
| Preview/Test context overrides | Manual (separate test Assembly) | ✅ `.onPreview` / `.onTest` modifier out of the box |
| Parallel tests | Manual reset between tests | ✅ Swift Testing `@Suite(.container)` via `@TaskLocal` |
| Maturity | 10+ years in production, de facto standard | Modern library, actively developed |
| SwiftUI specifics | Neutral | Tailored for SwiftUI/Observation |

**When Swinject is better:**
- Multi-module legacy is already on it — rewriting is more expensive
- Need autoregister (`container.autoregister(ProfileRepository.self, initializer: ProfileRepository.init)` without spelling out the constructor's arguments)
- Need **multiple** bindings keyed by `name:` with different arguments
- UIKit-first project, SwiftUI is used rarely

**When Factory is better:**
- New SwiftUI-first project
- A graph past the manual-DI threshold, monorepo or SPM modules
- Want to see the entire dependency surface at compile time
- Team prefers the property-wrapper style
- Critical: tests must run in parallel without reset headaches

**When neither fits:**
- A graph under the manual-DI threshold → manual DI on `lazy var` (`di-composition-root` → "DI: container vs manual graph")
- A whole TCA feature → `@Dependency` by Point-Free
