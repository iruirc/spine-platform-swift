# net-architecture — detailed guide

## Contents

- The HTTPClient Boundary
- Endpoint Design
- Interceptors / Middleware
- Cancellation
- Pagination
- Multipart, Downloads, Background URLSession
- WebSocket / SSE
- Caching
- Framework Comparison
- Testing

## The HTTPClient Boundary

<!-- typecheck -->
```swift
import Foundation

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public enum HTTPMethod: String, Sendable {
    case get = "GET", head = "HEAD", options = "OPTIONS", put = "PUT", delete = "DELETE"
    case post = "POST", patch = "PATCH"
}

public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: HTTPMethod
    public var queryItems: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval?
    public var cachePolicy: URLRequest.CachePolicy?
    public var idempotencyKey: String?     // see retry section
    public var requiresAuth: Bool          // see auth interceptor

    public init(
        url: URL,
        method: HTTPMethod,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval? = nil,
        cachePolicy: URLRequest.CachePolicy? = nil,
        idempotencyKey: String? = nil,
        requiresAuth: Bool = true
    ) {
        self.url = url
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.cachePolicy = cachePolicy
        self.idempotencyKey = idempotencyKey
        self.requiresAuth = requiresAuth
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
}
```

**Why this shape:**

- Returns raw `Data` + status — decoding belongs to `APIClient`, not transport.
- `idempotencyKey` is a first-class field, not a magic header — retry policy uses it to decide what's safe to retry.
- `requiresAuth` is a first-class field too — login and public endpoints set it to `false`, so the auth middleware leaves them alone instead of refreshing a token the user does not have.
- `Sendable` throughout — actors (`TokenRefresher`, `ItemsPaginator`) hold the client and call it from their own isolation.
- No `URLRequest` in the public surface — keeps the protocol portable to non-Foundation transports (e.g. `AsyncHTTPClient` on Linux for KMP/server-shared code).

## Endpoint Design

Three patterns. Pick **one per project** and stick with it.

### Pattern 1 — Per-endpoint typed methods on APIClient

<!-- typecheck -->
```swift
public protocol ItemsAPI: Sendable {
    func fetchItems(cursor: String?) async throws -> ItemsPage
    func createItem(_ draft: ItemDraft) async throws -> ItemDTO
    func deleteItem(id: String) async throws
}

final class HTTPItemsAPI: ItemsAPI {
    let http: HTTPClient
    let baseURL: URL

    init(http: HTTPClient, baseURL: URL) {
        self.http = http
        self.baseURL = baseURL
    }

    func fetchItems(cursor: String?) async throws -> ItemsPage {
        let req = HTTPRequest(
            url: baseURL.appending(path: "items"),
            method: .get,
            queryItems: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
        )
        let res = try await http.send(req)
        try APIErrorMapper.check(res)
        return try JSONDecoder.api.decode(ItemsPage.self, from: res.body)
    }

    // createItem(_:) and deleteItem(id:) follow the same shape
}
```

**Best for:** small/medium APIs (≤50 endpoints), strong autocomplete, easy mocking via protocol.

### Pattern 2 — Endpoint as value (Moya-style enum or struct)

```swift
public enum ItemsEndpoint: APIEndpoint {
    case list(page: Int)
    case create(ItemDraft)
    case delete(id: String)

    var path: String {
        switch self {
        case .list: return "items"
        case .create: return "items"
        case .delete(let id): return "items/\(id)"
        }
    }
    var method: HTTPMethod { /* ... */ }
    var task: APITask { /* ... */ }
}

final class APIClient {
    func send<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T { /* ... */ }
}
```

**Best for:** large APIs (100+ endpoints), strict cross-cutting transformation (uniform encoding/headers), Moya-style codebases. Trade-off: weaker autocomplete (return type erased to `T`).

### Pattern 3 — Generated client (OpenAPI)

See `net-openapi` skill. Generated `Client` exposes `try await client.listItems(.init(query: .init(page: page)))`. Wrap it in your `ItemsAPI` protocol so the rest of the app doesn't depend on generated types.

## Interceptors / Middleware

Cross-cutting concerns belong in composable middleware, not scattered through endpoints.

<!-- typecheck -->
```swift
public protocol HTTPMiddleware: Sendable {
    func intercept(
        _ request: HTTPRequest,
        next: (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse
}

final class MiddlewareHTTPClient: HTTPClient {
    let transport: HTTPClient
    let middlewares: [HTTPMiddleware]

    init(transport: HTTPClient, middlewares: [HTTPMiddleware]) {
        self.transport = transport
        self.middlewares = middlewares
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var chain: (HTTPRequest) async throws -> HTTPResponse = transport.send
        for middleware in middlewares.reversed() {
            let next = chain
            chain = { try await middleware.intercept($0, next: next) }
        }
        return try await chain(request)
    }
}
```

**Standard middleware stack (order matters — top to bottom):**

1. **Logging** (outermost — one entry per call, with its final status and total duration; the attempts Retry makes below it are not logged one by one) — log method/path/status/duration; **never log body or auth headers without PII redaction** (see `error-architecture`).
2. **Auth** — inject `Authorization` into `requiresAuth` requests; on 401 get the current token, refreshing only if it is still the rejected one, and retry once.
3. **Retry** — exponential backoff with jitter; idempotency-aware (see below).
4. **Headers / Telemetry** — `User-Agent`, request ID, trace headers.
5. **Transport** (innermost) — actual `URLSession`/Alamofire/Moya.

### Auth interceptor with token refresh

Naïve refresh has two races. Five parallel requests all see 401 and all five fire `/refresh`. And a request sent with the old token can get its 401 after the refresh has finished: it fires a second refresh, which ends the session when the server rotates refresh tokens. Solution: **a single in-flight refresh, and every 401 judged by the token its request carried.**

<!-- typecheck -->
```swift
struct Credentials: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
}

protocol CredentialStore: Sendable {
    func load() -> Credentials?
    func save(_ credentials: Credentials?)
}

enum AuthError: Error {
    case signedOut
    case refreshFailed(status: Int)
}

actor TokenRefresher {
    private let store: CredentialStore
    private let refreshClient: HTTPClient
    private let refreshURL: URL
    private var refreshTask: Task<Credentials, Error>?

    init(store: CredentialStore, refreshClient: HTTPClient, refreshURL: URL) {
        self.store = store
        self.refreshClient = refreshClient
        self.refreshURL = refreshURL
    }

    func currentToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let credentials = store.load() else { throw AuthError.signedOut }
        return credentials.accessToken
    }

    /// The token to retry with after a 401 for a request sent with `rejected`.
    func token(replacing rejected: String) async throws -> String {
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let credentials = store.load() else { throw AuthError.signedOut }
        guard credentials.accessToken == rejected else { return credentials.accessToken }
        let task = Task { try await refresh(credentials) }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.accessToken
    }

    private func refresh(_ credentials: Credentials) async throws -> Credentials {
        let body = try JSONEncoder().encode(["refreshToken": credentials.refreshToken])
        let request = HTTPRequest(url: refreshURL, method: .post, body: body, requiresAuth: false)
        let response = try await refreshClient.send(request)
        switch response.status {
        case 200..<300:
            let renewed = try JSONDecoder().decode(Credentials.self, from: response.body)
            store.save(renewed)
            return renewed
        case 400, 401:
            store.save(nil)
            throw AuthError.signedOut
        default:
            throw AuthError.refreshFailed(status: response.status)
        }
    }
}
```

<!-- typecheck -->
```swift
struct AuthMiddleware: HTTPMiddleware {
    let refresher: TokenRefresher

    func intercept(
        _ request: HTTPRequest,
        next: (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        guard request.requiresAuth else { return try await next(request) }
        let sent = try await refresher.currentToken()
        let response = try await next(request.bearer(sent))
        guard response.status == 401 else { return response }
        let current = try await refresher.token(replacing: sent)
        try Task.checkCancellation()
        return try await next(request.bearer(current))
    }
}

private extension HTTPRequest {
    func bearer(_ token: String) -> HTTPRequest {
        var request = self
        request.headers["Authorization"] = "Bearer \(token)"
        return request
    }
}

// Composition root: the refresh request gets its own chain, without AuthMiddleware.
func makeAPIHTTPClient(
    transport: HTTPClient,
    logging: HTTPMiddleware,
    credentials: CredentialStore,
    baseURL: URL
) -> HTTPClient {
    let refresher = TokenRefresher(
        store: credentials,
        refreshClient: MiddlewareHTTPClient(transport: transport, middlewares: [logging]),
        refreshURL: baseURL.appending(path: "auth/refresh")
    )
    let middlewares: [HTTPMiddleware] = [
        logging,
        AuthMiddleware(refresher: refresher),
        RetryMiddleware(policy: RetryPolicy()),
    ]
    return MiddlewareHTTPClient(transport: transport, middlewares: middlewares)
}
```

**Key invariants:**

- `actor TokenRefresher` — one refresh at a time; a 401 that arrives while it runs waits for it.
- A 401 is judged by the token its request carried. If the stored token is already a different one, a refresh has happened since: retry with it, and do not refresh again.
- 401 → retry **once.** If the retry also returns 401, propagate it.
- The refresh request travels through its own `HTTPClient` without `AuthMiddleware`. Sent through the same chain, it would wait for the refresh it is part of.
- `requiresAuth: false` on login and public endpoints — a signed-out user's login never reaches the refresher.
- Refresh rejected (400/401) → credentials cleared, `AuthError.signedOut`; route to the login screen via a separate `AuthEvents` stream (do NOT throw a UI message from the middleware). Any other failure keeps the credentials: a flaky network must not sign the user out.

### Retry policy

<!-- typecheck -->
```swift
struct RetryPolicy: Sendable {
    var maxAttempts = 3
    var baseDelay: Duration = .milliseconds(300)
    var maxDelay: Duration = .seconds(4)
    var retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504]

    /// The wait before the next attempt, or nil to hand `outcome` to the caller.
    func delay(
        after attempt: Int,
        of request: HTTPRequest,
        outcome: Result<HTTPResponse, Error>
    ) -> Duration? {
        guard attempt < maxAttempts, isIdempotent(request), !Task.isCancelled else { return nil }
        switch outcome {
        case .success(let response):
            guard retryableStatuses.contains(response.status) else { return nil }
            guard let value = header("Retry-After", in: response) else { return backoff(attempt) }
            guard let seconds = Int(value), .seconds(seconds) <= maxDelay else { return nil }
            return .seconds(seconds)
        case .failure(let error):
            return isTransient(error) ? backoff(attempt) : nil
        }
    }

    private func isIdempotent(_ request: HTTPRequest) -> Bool {
        switch request.method {
        case .get, .head, .options, .put, .delete: return true
        case .post, .patch: return request.idempotencyKey != nil
        }
    }

    private func isTransient(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }    // CancellationError too
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code)
    }

    private func header(_ name: String, in response: HTTPResponse) -> String? {
        response.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private func backoff(_ attempt: Int) -> Duration {
        let exponential = baseDelay * (1 << (attempt - 1))
        return min(maxDelay, exponential + exponential * Double.random(in: 0...0.3))
    }
}

struct RetryMiddleware: HTTPMiddleware {
    let policy: RetryPolicy

    func intercept(
        _ request: HTTPRequest,
        next: (HTTPRequest) async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        var attempt = 1
        while true {
            let outcome: Result<HTTPResponse, Error>
            do { outcome = .success(try await next(request)) } catch { outcome = .failure(error) }
            guard let delay = policy.delay(after: attempt, of: request, outcome: outcome) else {
                return try outcome.get()
            }
            try await Task.sleep(for: delay)
            attempt += 1
        }
    }
}
```

**Hard rules:**

- **Never auto-retry POST/PATCH without `Idempotency-Key`.** Double-charge bugs are real and ugly. See `error-architecture`.
- **Honor `Retry-After`** for 429/503 — it replaces the backoff. A wait longer than `maxDelay`, or a `Retry-After` in HTTP-date form, returns the response to the caller rather than retrying early.
- **Cancellation ends retrying** — `delay` returns `nil` in a cancelled task, `Task.sleep` throws `CancellationError`, and neither `CancellationError` nor `URLError.cancelled` counts as transient.
- **Bounded attempts** — 3 is a sane default; 10 turns transient outages into thundering herds.
- **Per-host circuit breaker** is the next step for production; out of scope for the skill.

## Cancellation

Cancellation must propagate from the View layer all the way down to `URLSession.dataTask`.

```swift
final class ItemListViewModel {
    private var loadTask: Task<Void, Never>?

    func onAppear() {
        loadTask = Task { @MainActor in
            do {
                items = try await repository.fetchItems()
            } catch is CancellationError {
                // silent — see error-architecture
            } catch {
                message = ErrorMapper.toUserMessage(error)
            }
        }
    }

    func onDisappear() {
        loadTask?.cancel()
    }
}
```

**Rules:**

- `URLSession` async methods (`data(for:)`) **already** propagate cancellation to the underlying task — no extra wiring needed. They report it as `URLError(.cancelled)`, not `CancellationError`, so the transport rethrows it as `CancellationError` (`URLSessionHTTPClient` and `AlamofireHTTPClient` below) and every layer above filters one type.
- Custom `HTTPClient` implementations **must** check `Task.isCancelled` before retry attempts and call `URLSessionDataTask.cancel()` if you maintain your own bridge.
- **`CancellationError` is not a user error** — never show it; never log at error level. Filter at the boundary that knows the user's intent (typically the ViewModel).
- Combine: use `.handleEvents(receiveCancel:)` to stop side effects; do NOT call `cancel()` on a publisher inside `sink` — store the `AnyCancellable` and drop it.

## Pagination

Three patterns. Choose based on what the API supports; never roll multiple in one app.

### Cursor-based (preferred for infinite feeds)

<!-- typecheck -->
```swift
public struct ItemsPage: Decodable, Sendable {
    public let items: [ItemDTO]
    public let nextCursor: String?     // nil = end
}

actor ItemsPaginator {                 // repository layer: maps API DTOs to Domain
    private let api: ItemsAPI
    private var cursor: String?
    private var isExhausted = false
    private var isLoading = false      // the actor re-enters at every await
    private(set) var items: [Item] = []

    init(api: ItemsAPI) {
        self.api = api
    }

    func loadNext() async throws -> [Item] {
        guard !isExhausted, !isLoading else { return items }
        isLoading = true
        defer { isLoading = false }
        let requested = cursor
        let page = try await api.fetchItems(cursor: requested)
        guard cursor == requested else { return items }   // reset() ran during the await
        items.append(contentsOf: page.items.map(Item.init(dto:)))
        cursor = page.nextCursor
        isExhausted = page.nextCursor == nil
        return items
    }

    func reset() { cursor = nil; isExhausted = false; items = [] }
}
```

### Offset / page-number (for stable, paginated lists)

```swift
let page = try await api.fetchItems(page: pageNumber, pageSize: 20)
```

Trade-off: **drift** — if items are added/deleted server-side between page loads, you see duplicates or skips. Use cursors for feeds, offsets only for stable archives.

### Streaming (`AsyncSequence`)

```swift
extension ItemsPaginator: AsyncSequence {
    typealias Element = [Item]
    /* AsyncIterator that yields each loaded page */
}

for try await page in paginator { /* update UI */ }
```

Cleanest API for the View layer; cancellation propagates naturally via `Task.cancel()`.

## Multipart, Downloads, Background URLSession

Keep these in dedicated specialized clients — don't pollute `HTTPClient` with multipart concerns.

<!-- typecheck -->
```swift
public protocol UploadClient {
    func upload(fileAt file: URL, to url: URL, mimeType: String, filename: String)
        async throws -> URL
}

public protocol DownloadClient {
    func download(_ url: URL) async throws -> URL  // local file URL
}
```

**Background URLSession** (when uploads must survive app suspension):

- Separate `URLSessionConfiguration.background(withIdentifier:)` instance — one per session ID; never share.
- Upload from a file: a background session rejects `uploadTask(with:from:)` with `Data`. The client takes a file and writes the multipart body to another file before it creates the task.
- Delegate-based, and the delegate owns each result. An awaiting continuation lives only as long as the process, while the transfer outlives it: record what each task is for (`taskDescription`) and let the delegate write the outcome where the app reads it.
- At launch, recreate the session with the same identifier and delegate before anything else — the system then delivers the events of tasks that finished while the app was not running.
- Implement `application(_:handleEventsForBackgroundURLSession:completionHandler:)`, store the completion handler, and call it on the main queue from `urlSessionDidFinishEvents(forBackgroundURLSession:)`.

## WebSocket / SSE

Native iOS has `URLSessionWebSocketTask`. Wrap it in an `AsyncStream` for the consumer:

```swift
public protocol RealtimeChannel {
    func messages() -> AsyncThrowingStream<RealtimeEvent, Error>
    func send(_ event: RealtimeEvent) async throws
    func close()
}
```

**Architectural notes:**

- Reconnect logic belongs in the channel implementation (exponential backoff, jitter), not the consumer.
- Keep one connection per logical channel; multiplex on top if needed — never open one socket per ViewModel.
- Heartbeat (ping every N seconds) — ALWAYS. iOS aggressively kills idle TCP sockets in background.
- For SSE there's no native API; use `URLSession.bytes(for:)` and parse the `text/event-stream` format yourself, or use `LDSwiftEventSource`.

## Caching

Two layers — pick deliberately.

| Layer | Implementation | When to use |
|---|---|---|
| HTTP-level | `URLCache`, `URLRequest.cachePolicy`, `Cache-Control` from server | Server controls freshness, opaque blobs (images, large JSON) |
| Repository-level | In-memory dict / `NSCache` / SQLite | Domain-specific freshness rules, offline-first, derived data |

**Hard rules:**

- **Never let `URLCache` keep authorized responses across accounts.** `Cache-Control: private` only keeps shared caches (proxies) out; `URLCache` is the app's private cache and may store the response. Have the server send `Cache-Control: no-store`, or give the authorized session no `URLCache`; if responses are cached, clear the session's `URLCache` at logout.
- **Cache invalidation** belongs to the Repository, not the View — when a `POST /items` succeeds, the Repository invalidates `items list` cache before returning.
- **Do not** cache 4xx/5xx responses unless you're implementing offline-first explicitly (then cache them as "last known error" with TTL).

Persistent storage strategies (Core Data, SwiftData, SQLite) — see `persistence-architecture` skill; for cached-DTO/entity schema evolution see `persistence-migrations`.

## Framework Comparison

| Framework | Style | Async | Interceptors | Codegen | When to pick |
|---|---|---|---|---|---|
| `URLSession` | Native, low-level | async/await ✅, Combine ✅ | Manual (your middleware) | — | **Default for new projects.** No dependency, full control. |
| Alamofire | Imperative request builder | async/await ✅, Combine ✅, RxSwift via extension | Built-in `RequestInterceptor` | — | Existing Alamofire codebases; multipart edge cases. |
| Moya | Declarative endpoint enum on top of Alamofire | No async API (bridge it, see below), Combine ✅, RxSwift ✅ | Plugins | — | Existing Moya codebases only. |
| Get (kean) | Modern minimal URLSession wrapper | async/await ✅ | Delegate-based | — | Greenfield projects that want less boilerplate than raw URLSession. |
| `swift-openapi-generator` | Generated client from OpenAPI spec | async/await ✅ | `ClientMiddleware` | ✅ from yaml | API has stable OpenAPI spec; want compile-time guarantees. See `net-openapi`. |
| Apollo iOS | GraphQL client (different paradigm) | async/await ✅ | Interceptors | ✅ from `.graphql` | GraphQL backend — out of scope here. |

**Recommendation matrix:**

- **New project, REST, no spec yet** → URLSession + the skill's HTTPClient pattern.
- **New project, REST, OpenAPI spec exists** → `swift-openapi-generator` wrapped in your `APIClient` protocol.
- **Existing Alamofire codebase** → keep Alamofire, adapt to `HTTPClient` protocol via `AlamofireHTTPClient`.
- **Existing Moya codebase** → keep it behind your `ItemsAPI` protocol, and do not start a new project on it: its last release, 15.0.3 (2022), has no async API.
- **GraphQL** → Apollo, separate skill territory.

### URLSession integration

<!-- typecheck -->
```swift
final class URLSessionHTTPClient: HTTPClient {
    let session: URLSession

    init(session: URLSession) {
        self.session = session
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = try toURLRequest(request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()      // URLSession's form of task cancellation
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        return HTTPResponse(
            status: http.statusCode,
            headers: http.allHeaderFields as? [String: String] ?? [:],
            body: data
        )
    }
}
```

Bootstrap in CR: one `URLSession(configuration: .default)` per environment; **do not** use `URLSession.shared` if you have custom delegate or auth challenge logic.

### Alamofire integration

```swift
import Alamofire

final class AlamofireHTTPClient: HTTPClient {
    let session: Session

    init(session: Session) {
        self.session = session
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let af = try toAFRequest(request)
        let response = await session.request(af).serializingData().response
        if response.error?.isExplicitlyCancelledError == true { throw CancellationError() }
        guard let http = response.response, let data = response.data else {
            throw response.error ?? HTTPClientError.invalidResponse
        }
        return HTTPResponse(
            status: http.statusCode,
            headers: http.allHeaderFields as? [String: String] ?? [:],
            body: data
        )
    }
}
```

Use Alamofire's `RequestInterceptor` only if you actively use Alamofire-specific features (auth challenge, custom server trust). Otherwise put interceptor logic in your own `HTTPMiddleware` chain — keeps it portable.

### Moya integration

```swift
import Moya
import CombineMoya

enum ItemsTarget: TargetType {
    case list(cursor: String?)
    case create(ItemDraft)
    /* baseURL, path, method, task, headers, sampleData */
}

let provider = MoyaProvider<ItemsTarget>(plugins: [NetworkLoggerPlugin(), AuthPlugin()])

// MoyaProvider is not Sendable; it holds only lets and a lock-guarded in-flight table.
final class MoyaItemsAPI: ItemsAPI, @unchecked Sendable {
    let provider: MoyaProvider<ItemsTarget>

    init(provider: MoyaProvider<ItemsTarget>) {
        self.provider = provider
    }

    func fetchItems(cursor: String?) async throws -> ItemsPage {
        // No async API in Moya: cancelling the awaiting task cancels the request.
        for try await response in provider.requestPublisher(.list(cursor: cursor)).values {
            try APIErrorMapper.check(response)
            return try JSONDecoder.api.decode(ItemsPage.self, from: response.data)
        }
        throw CancellationError()
    }
}
```

`MoyaProvider` is itself the transport — for Moya projects you can skip `HTTPClient` middleware and use Moya `PluginType` instead. **But** keep the `ItemsAPI` protocol layer above Moya so the rest of the app doesn't import Moya types. In a file that imports Moya, `Task` names `Moya.Task`; spell Swift's as `_Concurrency.Task`.

### swift-openapi-generator

Setup, integration, error mapping, mocking — see dedicated `net-openapi` skill.

## Testing

Mock at the **HTTPClient** boundary, not at `URLSession`. Two approaches:

### URLProtocol stub (transport-level, integration-style)

```swift
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown)); return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

func makeStubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}
```

**Use for:** integration tests verifying retry/auth/middleware end-to-end, contract tests against a recorded server response.

### Fake HTTPClient (unit-style)

<!-- typecheck -->
```swift
actor FakeHTTPClient: HTTPClient {
    private let respond: @Sendable (HTTPRequest) throws -> HTTPResponse
    private(set) var sentRequests: [HTTPRequest] = []

    init(respond: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) {
        self.respond = respond
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sentRequests.append(request)
        return try respond(request)
    }
}
```

**Use for:** ViewModel/Repository unit tests where you don't care about transport — only "did the call happen with the right query/body, what does this DTO turn into?" The `respond` closure sees the whole request, so two calls to one URL with different queries get different answers.

### Contract tests for endpoint encoding

<!-- typecheck -->
```swift
import XCTest

final class HTTPItemsAPITests: XCTestCase {
    func test_fetchItems_encodesCursorAsQuery() async throws {
        let fake = FakeHTTPClient { _ in
            HTTPResponse(status: 200, headers: [:], body: Data(#"{"items":[]}"#.utf8))
        }
        let api = HTTPItemsAPI(http: fake, baseURL: URL(string: "https://x")!)

        _ = try await api.fetchItems(cursor: "c3")

        let sent = await fake.sentRequests
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.url.absoluteString, "https://x/items")
        XCTAssertEqual(sent.first?.queryItems, [URLQueryItem(name: "cursor", value: "c3")])
        XCTAssertEqual(sent.first?.method, .get)
    }
}
```

**Always** verify URL composition for at least one happy-path test per endpoint — endpoint encoding bugs are silent until QA finds them in prod.
