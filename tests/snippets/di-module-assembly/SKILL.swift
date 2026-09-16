protocol UserServiceProtocol: Sendable {}
protocol AnalyticsServiceProtocol: Sendable {}
protocol SettingsFeatureDependencies {}
struct UserService: UserServiceProtocol {}
struct AnalyticsService: AnalyticsServiceProtocol {}
@MainActor final class AppDependencyContainer: AppDependencies {
    lazy var userService: UserServiceProtocol = UserService()
    lazy var analyticsService: AnalyticsServiceProtocol = AnalyticsService()
}
