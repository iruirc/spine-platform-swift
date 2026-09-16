protocol UserServiceProtocol: Sendable {}
protocol AnalyticsServiceProtocol: Sendable {}
struct MockUserService: UserServiceProtocol {}
struct MockAnalyticsService: AnalyticsServiceProtocol {}
struct ModuleComponents<View, ViewModel> {
    let view: View
    let viewModel: ViewModel
}
@MainActor final class ProfileViewModel {
    init(userService: UserServiceProtocol, analyticsService: AnalyticsServiceProtocol) {}
}
@MainActor final class DetailViewModel {
    init(itemId: String, userService: UserServiceProtocol) {}
}
@MainActor final class EditProfileViewModel {
    init(userService: UserServiceProtocol) {}
}
@MainActor final class ProfileViewController {
    init(viewModel: ProfileViewModel) {}
}
@MainActor final class DetailViewController {
    init(viewModel: DetailViewModel) {}
}
@MainActor final class EditProfileViewController {
    init(viewModel: EditProfileViewModel) {}
}
@MainActor protocol ProfileModuleFactory {
    func makeProfileModule() -> ModuleComponents<ProfileViewController, ProfileViewModel>
    func makeDetailModule(itemId: String)
        -> ModuleComponents<DetailViewController, DetailViewModel>
    func makeEditProfileModule()
        -> ModuleComponents<EditProfileViewController, EditProfileViewModel>
}
@MainActor protocol Router: AnyObject {}
@MainActor final class MockRouter: Router {
    var pushedViewController: AnyObject?
}
@MainActor protocol CoordinatorFactory {}
@MainActor final class MockCoordinatorFactory: CoordinatorFactory {}
@MainActor final class ProfileCoordinator {
    init(router: Router, coordinatorFactory: CoordinatorFactory, factory: ProfileModuleFactory) {}
    func start() {}
}
