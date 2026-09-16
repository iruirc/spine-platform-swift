import UIKit

struct Item {
    let id: String
}
enum FeatureResult {
    case logout
}
struct ModuleComponents<View, ViewModel> {
    let view: View
    let viewModel: ViewModel
}
final class FeatureViewController: UIViewController {}
@MainActor final class FeatureViewModel {
    var onItemSelected: ((Item) -> Void)?
    var onComplete: ((FeatureResult) -> Void)?
}
final class DetailCoordinator: BaseCoordinator {
    var onFinish: (() -> Void)?
}
final class AuthCoordinator: BaseCoordinator {
    var onFinish: (() -> Void)?
}
@MainActor protocol FeatureModuleFactory {
    func makeFeatureModule() -> ModuleComponents<FeatureViewController, FeatureViewModel>
}
@MainActor protocol CoordinatorFactory {
    func makeDetailCoordinator(router: Router, item: Item) -> DetailCoordinator
    func makeAuthCoordinator(router: Router) -> AuthCoordinator
    func makeTabBarCoordinator(router: Router) -> Coordinator
    func makeHomeCoordinator(router: Router) -> Coordinator
    func makeProfileCoordinator(router: Router) -> Coordinator
}
extension AppCoordinator {
    var userIsLoggedIn: Bool { false }
}
final class MockFeatureModuleFactory: FeatureModuleFactory {
    let viewModel = FeatureViewModel()
    func makeFeatureModule() -> ModuleComponents<FeatureViewController, FeatureViewModel> {
        ModuleComponents(view: FeatureViewController(), viewModel: viewModel)
    }
}
final class MockCoordinatorFactory: CoordinatorFactory {
    var lastCreatedCoordinator: Coordinator?
    func makeDetailCoordinator(router: Router, item: Item) -> DetailCoordinator {
        let coordinator = DetailCoordinator()
        lastCreatedCoordinator = coordinator
        return coordinator
    }
    func makeAuthCoordinator(router: Router) -> AuthCoordinator { AuthCoordinator() }
    func makeTabBarCoordinator(router: Router) -> Coordinator { BaseCoordinator() }
    func makeHomeCoordinator(router: Router) -> Coordinator { BaseCoordinator() }
    func makeProfileCoordinator(router: Router) -> Coordinator { BaseCoordinator() }
}
