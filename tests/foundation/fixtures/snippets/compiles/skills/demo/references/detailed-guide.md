# demo — detailed guide

<!-- typecheck -->
```swift
import Testing
import XCTest

@Test func addsUp() { #expect(1 + 1 == 2) }

final class AdditionTests: XCTestCase {
    func testAddsUp() { XCTAssertEqual(Adder.sum(1, 1), 2) }
}
```
