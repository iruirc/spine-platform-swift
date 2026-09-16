import Foundation

protocol UseCase: Sendable {}
struct User: Identifiable, Sendable {
    let id: UUID
}
struct Profile: Sendable {}
struct Post: Sendable {}
struct ProfileScreenData: Sendable {
    let profile: Profile
    let posts: [Post]
    let followers: [User]
}
protocol ProfileRepository: Sendable {
    func fetch(_ id: User.ID) async throws -> Profile
}
protocol PostsRepository: Sendable {
    func recent(by id: User.ID) async throws -> [Post]
}
protocol SocialRepository: Sendable {
    func followers(of id: User.ID) async throws -> [User]
}
struct Photo: Identifiable, Sendable {
    let id: UUID
}
protocol PhotoUploadAPI: Sendable {
    func upload(_ photo: Photo) async throws
}
struct RawItem: Sendable {}
struct Item: Sendable {}
func expensiveSyncTransform(_ raw: RawItem) -> Item { Item() }
