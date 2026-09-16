struct FeatureEntity {}
protocol FeatureServiceProtocol {
    func fetchItems(completion: @escaping @Sendable (Result<[FeatureEntity], Error>) -> Void)
}
@MainActor final class FeaturePresenter: FeatureInteractorOutputProtocol {
    func didFetchItems(_ items: [FeatureEntity]) {}
    func didFailFetchingItems(_ error: Error) {}
}
