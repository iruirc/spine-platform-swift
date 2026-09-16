import Combine
import Foundation

struct Item {
    let id: String
}
struct ItemCellModel {
    init(_ item: Item) {}
}
protocol FeatureServiceProtocol {
    func fetchItems() -> AnyPublisher<[Item], Error>
}
final class MockFeatureService: FeatureServiceProtocol {
    var stubbedResult: AnyPublisher<[Item], Error> = Empty().eraseToAnyPublisher()
    func fetchItems() -> AnyPublisher<[Item], Error> { stubbedResult }
}
extension FeatureViewController {
    func setupUI() {}
    func showErrorAlert(_ message: String) {}
}
