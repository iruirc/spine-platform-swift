import Foundation

struct FeatureEntity: Sendable {
    let id: String
    let title: String
    let createdAt: Date
}
struct FeatureItemViewModel {
    init(entity: FeatureEntity) {}
}
extension FeatureViewController {
    func setupUI() {}
}
