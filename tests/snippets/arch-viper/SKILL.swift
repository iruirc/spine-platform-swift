import Foundation

protocol FeatureServiceProtocol: Sendable {
    func fetchItems() async throws -> [FeatureEntity]
}
enum NetworkError: Error {
    case timeout
}
extension DateFormatter {
    static let shortDate = DateFormatter()
}
extension FeatureViewController {
    func setupUI() {}
}
final class MockFeatureView: FeatureViewProtocol {
    var showLoadingCalled = false
    var hideLoadingCalled = false
    var shownItems: [FeatureItemViewModel]?
    var shownErrorMessage: String?
    func showItems(_ items: [FeatureItemViewModel]) { shownItems = items }
    func showLoading() { showLoadingCalled = true }
    func hideLoading() { hideLoadingCalled = true }
    func showError(_ message: String) { shownErrorMessage = message }
}
final class MockFeatureRouter: FeatureRouterProtocol {
    var navigatedItem: FeatureEntity?
    func navigateToDetail(for item: FeatureEntity) { navigatedItem = item }
    func dismiss() {}
}
@MainActor final class MockFeatureService: FeatureServiceProtocol {
    var stubbedItems: [FeatureEntity] = []
    var stubbedError: Error?
    func fetchItems() async throws -> [FeatureEntity] {
        if let stubbedError { throw stubbedError }
        return stubbedItems
    }
}
