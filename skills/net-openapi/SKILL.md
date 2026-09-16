---
name: net-openapi
description: "Use when generating a Swift API client from an OpenAPI spec — Apple's swift-openapi-generator (SPM plugin), generated types/operations/middleware, transports (URLSession / AsyncHTTPClient), wrapping the generated Client in your own APIClient protocol, error mapping from generated Output enums to domain errors, mocking the generated client, server-side stubs, alternatives (CreateAPI, openapi-generator-cli)."
---

# OpenAPI Code Generation

Architectural recipe for using **`swift-openapi-generator`** (Apple's official tool) to generate a Swift API client from an OpenAPI 3.x spec, and wiring it into a layered iOS app **without leaking generated types past the network adapter**.

> **Related skills:**
> - `net-architecture` — overall network layering, HTTPClient/APIClient boundary, interceptors, retry. This skill plugs in as one transport choice.
> - `error-architecture` — mapping generated `Output` cases to domain/UI errors at the Repository boundary
> - `di-composition-root` — where the generated `Client` and its transport are bootstrapped
> - `di-module-assembly` — registering API surfaces into feature modules
> - `pkg-spm-design` — when the OpenAPI client lives in its own SPM package

## Why This Skill Exists

Hand-written API clients drift:

- DTOs renamed on backend, app keeps the old name → silent decode failure → empty UI in prod.
- New endpoint added → developer must read the swagger PDF, type out `URL` and `Codable` types by hand, miss a required query parameter.
- Optional vs required fields diverge between spec and code → `nil`-crash in production.
- Multiple developers write parallel API clients with slightly different decoders.

**Codegen flips the equation:** the spec is the source of truth, the Swift client is recompiled from it. Spec changes that break the client surface fail at compile time, not at runtime.

## What `swift-openapi-generator` Is

Apple-supported (announced WWDC 2023, GitHub `apple/swift-openapi-generator`):

- **Build-time SPM plugin** — runs `openapi-generator` during `swift build`; no checked-in generated code.
- Reads `openapi.yaml` (or `.json`), produces `Types.swift`, `Client.swift`, `Server.swift`.
- **Modular transports** — generator emits a `ClientTransport` protocol; you pick a transport package (URLSession, AsyncHTTPClient, custom).
- Async/await native; no Combine/RxSwift in the generated surface.
- Supports OpenAPI **3.0 and 3.1**, with **preliminary 3.2 support** in current 1.x releases. OpenAPI 2.0 / Swagger is not supported.

**Three packages you'll add:**

| Package | Purpose |
|---|---|
| `apple/swift-openapi-generator` | Build-time plugin (codegen) |
| `apple/swift-openapi-runtime` | Runtime types and protocols used by generated code |
| `apple/swift-openapi-urlsession` (or `-async-http-client`) | Concrete `ClientTransport` |

## Package.swift Setup

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyAPIClient",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "MyAPIClient", targets: ["MyAPIClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MyAPIClient",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
            ]
        ),
    ]
)
```

**File layout inside the target:**

```
Sources/MyAPIClient/
├── openapi.yaml            ← spec (input)
├── openapi-generator-config.yaml
├── APIClient.swift         ← your wrapper (output of this skill)
├── Mappers/
│   └── ItemMapper.swift    ← generated schema → ItemDTO
└── Errors/
    └── APIErrorMapper.swift
```

Generator output (`Types.swift`, `Client.swift`, `Server.swift`) is **not committed** — built fresh on every `swift build`.

## Generator Configuration

`openapi-generator-config.yaml`:

```yaml
generate:
  - types
  - client
accessModifier: internal      # generated code stays inside the SPM target
filter:
  paths:
    - /items
    - /items/{id}
    - /auth/login
    - /auth/refresh
```

**Why `accessModifier: internal`:** generated types are an implementation detail of `MyAPIClient`. The rest of the app sees only your `APIClient` protocol and Domain types. **Never** make generated types `public`.

**`filter`** lets you generate a subset for incremental adoption — useful when migrating a hand-written client endpoint by endpoint.

**Version discipline:** the snippets in this skill reflect the 1.x runtime shape
at the time of writing. Pin generator/runtime/transport versions in
`Package.resolved`, and when upgrading, compile-check custom
`ClientMiddleware` / `ClientTransport` signatures against the protocols emitted
by the pinned generator before copying examples forward.

## What Gets Generated

Given a spec endpoint:

```yaml
paths:
  /items/{id}:
    get:
      operationId: getItem
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: string }
      responses:
        '200':
          content:
            application/json:
              schema: { $ref: '#/components/schemas/Item' }
        '404':
          description: Not found
```

The generator emits roughly:

```swift
// In Types.swift
internal enum Components {
    enum Schemas {
        struct Item: Codable, Hashable, Sendable {
            var id: String
            var name: String
        }
    }
}

internal enum Operations {
    enum getItem {
        struct Input: Sendable, Hashable {
            var path: Path
            struct Path: Sendable, Hashable { var id: String }
        }
        @frozen enum Output: Sendable, Hashable {
            case ok(OK)
            case notFound(NotFound)
            case undocumented(statusCode: Int, UndocumentedPayload)

            struct OK: Sendable, Hashable {
                var body: Body
                @frozen enum Body: Sendable, Hashable {
                    case json(Components.Schemas.Item)
                }
            }
            struct NotFound: Sendable, Hashable { /* ... */ }
        }
    }
}

// In Client.swift
internal protocol APIProtocol: Sendable {
    func getItem(_ input: Operations.getItem.Input) async throws -> Operations.getItem.Output
}

internal struct Client: APIProtocol {
    init(serverURL: URL, transport: any ClientTransport, middlewares: [any ClientMiddleware] = [])
    func getItem(_ input: Operations.getItem.Input) async throws -> Operations.getItem.Output { /* generated */ }
}
```

**Key shapes:**

- **`Output` is an enum** of all documented status codes. `.undocumented` covers anything the spec doesn't list.
- Each documented response has its own associated value with a typed body.
- Switching on `Output` is exhaustive at compile time — when the spec adds a `409 Conflict`, the compiler tells you to handle it.

## Wrapping the Generated Client

**Rule: the rest of the app must not see generated types.** Wrap `Client` in your own protocol that returns DTOs *you* defined; the Repository maps them to Domain types (`net-architecture` → "Core Shape").

```swift
// Public surface — used by the rest of the app
public protocol ItemsAPI: Sendable {
    func fetchItem(id: String) async throws -> ItemDTO    // app-owned DTO, not a generated type
    func listItems() async throws -> [ItemDTO]
}

// Internal adapter — sees both worlds
struct GeneratedItemsAPI: ItemsAPI {
    let client: APIProtocol
    let mapper: ItemMapper

    func fetchItem(id: String) async throws -> ItemDTO {
        let response = try await client.getItem(.init(path: .init(id: id)))
        switch response {
        case .ok(let ok):
            switch ok.body {
            case .json(let item): return mapper.toDTO(item)
            }
        case .notFound:
            throw ItemsAPIError.notFound
        case .undocumented(let status, _):
            throw ItemsAPIError.unexpectedStatus(status)
        }
    }

    // listItems() follows the same shape
}
```

**Why this matters:**

- Swap `swift-openapi-generator` for hand-written or another generator — only the adapter changes.
- Tests of upstream code (Repository, ViewModel) mock `ItemsAPI`, never the generated `Client`.
- Spec rename of `getItem` → `getItemById` is one place to update (the adapter), not 50 ViewModels.

## Composition Root

```swift
// AppDependencyContainer (manual DI) or Swinject Assembly
let transport = URLSessionTransport(
    configuration: .init(session: .shared)
)

let middlewares: [any ClientMiddleware] = [
    AuthMiddleware(refresher: tokenRefresher, publicOperations: ["login"]),
    LoggingMiddleware(logger: networkLogger),
    RetryMiddleware(policy: .default),
]

let generatedClient = Client(
    serverURL: env.apiBaseURL,
    transport: transport,
    middlewares: middlewares
)

let itemsAPI: ItemsAPI = GeneratedItemsAPI(
    client: generatedClient,
    mapper: ItemMapper()
)
```

See `di-composition-root` and `net-architecture` for where this fits in the broader bootstrap.

## Middleware

The generator defines `ClientMiddleware` (different protocol from the one in `net-architecture`'s `HTTPMiddleware` — they live in different layers):

```swift
import Foundation
import HTTPTypes
import Networking      // TokenRefresher from net-architecture
import OpenAPIRuntime

struct AuthMiddleware: ClientMiddleware {
    let refresher: TokenRefresher
    let publicOperations: Set<String>      // operation IDs sent without a token, e.g. "login"

    func intercept(
        _ request: HTTPTypes.HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPTypes.HTTPRequest, HTTPBody?, URL) async throws
            -> (HTTPTypes.HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
        if publicOperations.contains(operationID) { return try await next(request, body, baseURL) }
        var req = request
        let sent = try await refresher.currentToken()
        req.headerFields[.authorization] = "Bearer \(sent)"

        let (response, responseBody) = try await next(req, body, baseURL)
        guard response.status.code == 401 else { return (response, responseBody) }

        let current = try await refresher.token(replacing: sent)
        req.headerFields[.authorization] = "Bearer \(current)"
        return try await next(req, body, baseURL)
    }
}
```

**`HTTPTypes.HTTPRequest` / `HTTPTypes.HTTPResponse` come from `swift-http-types`** (Apple's typed HTTP primitives), not Foundation. The generator standardises on these to be portable across transports (URLSession on Apple, AsyncHTTPClient on Linux). `Networking` stands for your module with the `net-architecture` types; it declares its own `HTTPRequest` and `HTTPResponse`, so a file that imports both modules names each with its module. The refresh and the 401 check follow `net-architecture`'s token refresher: a 401 refreshes only while the rejected token is still the stored one.

**Architectural choice — middleware in `ClientMiddleware` vs in your own `HTTPMiddleware` (`net-architecture`):**

- **Use generator `ClientMiddleware`** when the OpenAPI client is your only HTTP surface — auth/logging/retry sit closest to the codegen layer.
- **Use your own `HTTPMiddleware`** when you have multiple HTTP surfaces (generated + hand-written legacy + analytics SDK) and want one place for cross-cutting policies. Then wrap a custom `ClientTransport` that forwards through your `HTTPClient`.

## Custom Transport (bridging to your HTTPClient)

```swift
import Foundation
import HTTPTypes
import Networking      // HTTPClient, HTTPRequest, HTTPResponse from net-architecture
import OpenAPIRuntime

struct HTTPClientTransport: ClientTransport {
    let http: any Networking.HTTPClient
    let publicOperations: Set<String>      // sent with requiresAuth: false, e.g. "login"

    func send(
        _ request: HTTPTypes.HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPTypes.HTTPResponse, HTTPBody?) {
        // request.path carries the encoded query; URL.appending(path:) would escape its "?".
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let target = URLComponents(string: request.path ?? "") else {
            throw URLError(.badURL)
        }
        components.percentEncodedPath += target.percentEncodedPath
        components.percentEncodedQuery = target.percentEncodedQuery
        guard let url = components.url,
              let method = HTTPMethod(rawValue: request.method.rawValue) else {
            throw URLError(.badURL)
        }
        var bodyData: Data?
        if let body { bodyData = try await Data(collecting: body, upTo: .max) }
        let fields = request.headerFields.map { ($0.name.rawName, $0.value) }
        let myRes = try await http.send(Networking.HTTPRequest(
            url: url,
            method: method,
            headers: Dictionary(fields, uniquingKeysWith: { "\($0), \($1)" }),
            body: bodyData,
            requiresAuth: !publicOperations.contains(operationID)
        ))
        var responseFields = HTTPFields()
        for (name, value) in myRes.headers {
            guard let name = HTTPField.Name(name) else { continue }
            responseFields.append(HTTPField(name: name, value: value))
        }
        let response = HTTPTypes.HTTPResponse(
            status: .init(code: myRes.status),
            headerFields: responseFields
        )
        return (response, HTTPBody(myRes.body))
    }
}
```

This lets you keep ALL middleware in your `HTTPClient` chain (auth/retry/logging/telemetry) and use the generated `Client` purely for typed encoding/decoding.

## Error Mapping

Map generated `Output` enums to your `RepositoryError` / `DomainError` at the adapter boundary. **Never** let generated types reach the ViewModel.

```swift
enum ItemsRepositoryError: Error {
    case notFound
    case unauthorized
    case networkUnavailable
    case decoding(Error)
    case unknown(Error)
}

struct ItemsRepository {
    let api: ItemsAPI

    func fetchItem(id: String) async throws(ItemsRepositoryError) -> Item {
        do {
            let dto = try await api.fetchItem(id: id)
            return Item(dto: dto)
        } catch ItemsAPIError.notFound {
            throw .notFound
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw .networkUnavailable
        } catch let error as DecodingError {
            throw .decoding(error)
        } catch {
            throw .unknown(error)
        }
    }
}
```

Cross-link `error-architecture` — full per-layer mapping rules and the `UserMessage` boundary live there.

## Mocking the Generated Client

You have two options. Both work; pick by team preference.

### Option A — Mock the generated `APIProtocol` (closer to the metal)

```swift
struct MockAPIProtocol: APIProtocol {
    var getItemHandler: (Operations.getItem.Input) async throws -> Operations.getItem.Output

    func getItem(_ input: Operations.getItem.Input) async throws -> Operations.getItem.Output {
        try await getItemHandler(input)
    }
}

func test_fetchItem_whenNotFound_throwsNotFound() async {
    let mock = MockAPIProtocol(getItemHandler: { _ in .notFound(.init()) })
    let api = GeneratedItemsAPI(client: mock, mapper: ItemMapper())

    do {
        _ = try await api.fetchItem(id: "42")
        XCTFail("expected throw")
    } catch ItemsAPIError.notFound {
        // ok
    } catch {
        XCTFail("wrong error: \(error)")
    }
}
```

**When:** testing the adapter itself (mapping logic, error translation).

### Option B — Mock your `ItemsAPI` protocol (preferred for upstream)

```swift
struct MockItemsAPI: ItemsAPI {
    var fetchItemHandler: @Sendable (String) async throws -> ItemDTO
    var listItemsHandler: @Sendable () async throws -> [ItemDTO] = { [] }
    func fetchItem(id: String) async throws -> ItemDTO { try await fetchItemHandler(id) }
    func listItems() async throws -> [ItemDTO] { try await listItemsHandler() }
}
```

**When:** testing Repository/UseCase/ViewModel — they shouldn't know `APIProtocol` exists.

## Server Stub for Integration Tests

The generator can also emit a `Server` protocol — useful for spinning up an in-process stub server in tests.

```yaml
# openapi-generator-config.yaml (test target)
generate:
  - types
  - server
```

```swift
struct StubItemsServer: APIProtocol {
    func getItem(_ input: Operations.getItem.Input) async throws -> Operations.getItem.Output {
        if input.path.id == "42" {
            return .ok(.init(body: .json(.init(id: "42", name: "Answer"))))
        }
        return .notFound(.init())
    }
}
```

Pair with the generator's local-loop transport (or a custom one) to drive integration tests against a known-good response set without booting a real HTTP server.

## Spec Evolution Workflow

1. **Backend ships spec change** — `openapi.yaml` updated in shared repo.
2. **iOS pulls new spec** — `git submodule update` or copy file in.
3. **`swift build`** — generator runs, regenerated types may break compilation if:
   - Required field removed → consumers stop compiling. Good.
   - New required field → constructor signature changes. Good.
   - New status code documented → `switch` is no longer exhaustive. Good.
4. **Adapter updated** — adapter code changes are localized; the rest of the app keeps compiling.
5. **Test suite confirms** — adapter unit tests verify mapping for new fields/codes.

**This is the value:** breaking changes surface at compile time, in one place, before they reach production.

## Alternatives (when not to use swift-openapi-generator)

| Tool | When |
|---|---|
| **CreateAPI** (kean) | Older REST projects, simpler output, no SPM plugin (CLI tool); fewer guarantees but less ceremony. |
| **openapi-generator-cli** (community, Java) | Need exotic generator options, multi-language org-wide standardization, OpenAPI 2.0 support. Output is less idiomatic Swift. |
| **Hand-written client** | Spec doesn't exist; backend churns daily; team is 1-2 devs and adoption cost > ROI. |
| **Sourcery + custom templates** | Codegen from non-OpenAPI source (e.g. internal IDL). |
| **Apollo iOS** | GraphQL backend — different paradigm, separate skill territory. |

**When `swift-openapi-generator` is the wrong choice:**

- No OpenAPI spec exists and you're not going to maintain one. Codegen without a source of truth is just hand-writing with extra steps.
- Spec is wildly out of sync with backend reality (you'll generate phantoms).
- Backend uses `oneOf`/discriminator patterns the generator handles awkwardly. Check the GitHub issues for your specific shape before committing.

## Common Mistakes

1. **Making generated types `public`** — couples the rest of the app to the spec. Future spec rename = thousands of code changes. Keep `accessModifier: internal` and wrap.
2. **Returning `Operations.X.Output` from your Repository** — leaks generated enum upward. Map at the adapter boundary.
3. **No `.undocumented` handling** — generator emits `.undocumented(statusCode:)` for any response not in the spec. If you don't handle it, you crash at runtime when staging returns a maintenance HTML page.
4. **Committing generated code** — defeats the point. Generator runs on `swift build`; treat output as build artifact.
5. **One giant `openapi.yaml` for the whole app** — slow builds, big diffs. Split per bounded context (Auth, Items, Billing) → separate SPM targets.
6. **Mixing generator middleware and your own HTTPClient middleware** — auth gets injected twice, retry retries the retry. Pick one chain.
7. **Skipping mapping for "simple" endpoints** — "this DTO has the same fields as Domain, why bother mapping?" Six months later spec adds a field, Domain doesn't want it, you've already shipped the generated type into the ViewModel.
8. **Decoding generated DTO date as ISO8601 in adapter, but server uses Unix epoch** — generator decodes per spec; if spec says `format: date-time` you get ISO8601. Spec mismatch = decode failure. Verify at integration level, not by reading docs.
9. **No CI step that runs codegen** — local builds pass, CI uses a different generator version, prod build differs. Pin generator version in `Package.resolved`; run `swift build` in CI as a smoke check.
10. **Filtering paths and forgetting to update the filter** — new endpoint added to spec, your `filter` doesn't include it, generator silently skips. Periodically audit `filter` against full spec or remove the filter once you've fully adopted.
