protocol UserServiceProtocol: Sendable {}
protocol AnalyticsServiceProtocol: Sendable {}
protocol ImageLoaderProtocol: Sendable {}
protocol AppSettingsManagerProtocol: Sendable {}
protocol HTTPClient: Sendable {}
protocol HomeFeatureDependencies {}
struct URLSessionHTTPClient: HTTPClient {}
struct UserService: UserServiceProtocol {
    init(networkClient: HTTPClient) {}
}
struct AnalyticsService: AnalyticsServiceProtocol {}
struct ImageLoader: ImageLoaderProtocol {
    init(networkClient: HTTPClient) {}
}
struct AppSettingsManager: AppSettingsManagerProtocol {}
