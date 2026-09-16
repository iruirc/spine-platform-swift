final class AnalyticsService {
    weak var userService: UserService?
}
final class UserService {
    let analytics: AnalyticsService
    init(analytics: AnalyticsService) {
        self.analytics = analytics
    }
}
