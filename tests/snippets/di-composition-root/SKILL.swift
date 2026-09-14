protocol Logger: Sendable {}
protocol HTTPClient: Sendable {}
protocol UserServiceProtocol: Sendable {}
protocol AnalyticsServiceProtocol: Sendable {}
protocol ImageLoaderProtocol: Sendable {}
@MainActor protocol AppDependencies {
    var userService: UserServiceProtocol { get }
    var analyticsService: AnalyticsServiceProtocol { get }
    var imageLoader: ImageLoaderProtocol { get }
}
struct AppConfig: Sendable {
    let bundleId: String
    static func fromBundle() -> AppConfig { AppConfig(bundleId: "") }
}
struct OSLogger: Logger { init(subsystem: String) {} }
struct URLSessionHTTPClient: HTTPClient { init(config: AppConfig, logger: Logger) {} }
struct KeychainStorage: Sendable { init(service: String) {} }
struct ImageCache: Sendable { init(maxBytes: Int) {} }
struct UserService: UserServiceProtocol {
    init(networkClient: HTTPClient, storage: KeychainStorage, logger: Logger) {}
}
struct AnalyticsService: AnalyticsServiceProtocol { init(config: AppConfig, logger: Logger) {} }
struct ImageLoader: ImageLoaderProtocol { init(networkClient: HTTPClient, cache: ImageCache) {} }
