@MainActor class BaseCoordinator {}
struct Item {}
enum FeatureResult {
    case logout
}
extension FeatureCoordinator {
    var onFinish: ((FeatureResult) -> Void)? { nil }
    func showDetail(for item: Item) {}
    func showSettings() {}
}
