# demo

<!-- typecheck -->
```swift
final class Draft {
    var text = ""
    func save() async {}
}

@MainActor
final class Editor {
    private let draft = Draft()
    func close() async { await draft.save() }
}
```
