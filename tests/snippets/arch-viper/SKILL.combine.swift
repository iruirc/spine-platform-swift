import Combine

struct FeatureEntity {}
protocol FeatureServiceProtocol {
    func fetchItems() -> AnyPublisher<[FeatureEntity], Error>
}
