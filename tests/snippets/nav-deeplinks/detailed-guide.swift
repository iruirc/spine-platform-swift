import UIKit
import SwiftUI

@MainActor
final class AppDependencyContainer {
    let deepLinks = DeepLinkRouter(isAuthed: { true }, requiresAuth: { _ in false })
    func makeAppCoordinator(window: UIWindow) -> AppCoordinator { AppCoordinator() }
}

@MainActor
final class AppCoordinator {
    func start() {}
    func handleDeepLink(_ route: Route) {}
}

struct HomeView: View {
    var body: some View { EmptyView() }
}

struct RouteView: View {
    let route: Route
    var body: some View { EmptyView() }
}
