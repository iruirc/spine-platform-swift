import SwiftUI

struct Item: Identifiable {
    let id: String
    let title: String
}
struct EditItemView: View {
    let item: Item
    var body: some View { EmptyView() }
}
