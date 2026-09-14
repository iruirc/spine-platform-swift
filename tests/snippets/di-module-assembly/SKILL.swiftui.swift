import Observation
import SwiftUI

protocol AppSettingsManagerProtocol: Sendable {}
@MainActor protocol SettingsFeatureDependencies {
    var appSettingsManager: AppSettingsManagerProtocol { get }
}
struct ModuleComponents<View, ViewModel> {
    let view: View
    let viewModel: ViewModel
}
@MainActor final class SettingsViewModel {
    init(settings: AppSettingsManagerProtocol) {}
}
struct SettingsView: View {
    let viewModel: SettingsViewModel
    var body: some View { EmptyView() }
}
struct HomeView: View {
    var body: some View { EmptyView() }
}
struct SettingsRoute: Hashable {}
@MainActor @Observable final class AppRouter {
    var path = NavigationPath()
}
@MainActor protocol SettingsModuleFactory {
    func makeSettingsModule() -> ModuleComponents<SettingsView, SettingsViewModel>
}
