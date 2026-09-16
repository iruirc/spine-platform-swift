struct Item {}
struct ItemDTO {
    func toDomain() throws -> Item { Item() }
    static func fromDomain(_ item: Item) -> ItemDTO { ItemDTO() }
}
