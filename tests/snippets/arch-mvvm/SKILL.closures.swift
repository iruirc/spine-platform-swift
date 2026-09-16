import Foundation

struct Item: Sendable {
    let id: String
}
struct ItemCellModel {
    init(_ item: Item) {}
}
protocol FeatureServiceProtocol {
    func fetchItems(completion: @escaping @Sendable (Result<[Item], Error>) -> Void)
}
final class MockFeatureService: FeatureServiceProtocol {
    var stubbedResult: Result<[Item], Error> = .success([])
    func fetchItems(completion: @escaping @Sendable (Result<[Item], Error>) -> Void) {
        completion(stubbedResult)
    }
}
