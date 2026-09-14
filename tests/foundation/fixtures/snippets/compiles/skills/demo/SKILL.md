# demo

A marked block leans on a stub from the prelude:

<!-- typecheck -->
```swift
import Foundation

struct Greeting {
    let greeter: any Greeter
    func text() -> String { greeter.greet("world") }
}
```

A later block of the same group sees the earlier one:

<!-- typecheck -->
```swift
func makeGreeting() -> Greeting { Greeting(greeter: EnglishGreeter()) }
```

A block of another group compiles on its own, so it may redeclare a type:

<!-- typecheck: alt -->
```swift
import SwiftUI

struct Greeting: View {
    var body: some View { Text("Hello") }
}
```

An unmarked block is not compiled:

```swift
let broken: Int = "not an int"
```
