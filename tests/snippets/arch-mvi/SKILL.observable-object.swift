struct Item: Sendable {}
struct ItemListState {}
enum ItemListIntent {
    case viewAppeared
}
struct ItemListEffect {
    let run: () async -> ItemListIntent
}
func reduceItemList(
    _ state: inout ItemListState,
    _ intent: ItemListIntent,
    _ load: @Sendable @escaping () async throws -> [Item]
) -> ItemListEffect? {
    nil
}
