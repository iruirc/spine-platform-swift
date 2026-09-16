struct Item: Sendable {}
struct Photo: Sendable {}
struct FetchItemsUseCase: Sendable {
    func execute() async throws -> [Item] { [] }
}
actor PhotoUploader {
    func enqueue(_ photo: Photo) {}
}
