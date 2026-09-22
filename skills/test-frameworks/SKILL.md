---
name: test-frameworks
description: Data for whoever writes or reads a test on this platform — one section per value of the manifest's `tests` axis (XCTest, Swift Testing, Quick+Nimble) and the surfaces that force a framework whatever the axis says. Which value a given file takes is decided by `spine-toolkit:test-authoring`; this skill says what that value looks like in code and in a failing run.
---

# Test Frameworks

`spine-toolkit:test-authoring` picks the framework for the file being written. This skill says what
that pick means in code. Read the one section named after the value, not all three.

## Forced by surface

Where only one framework can drive a surface, it wins over the axis value.

| Surface | Framework | Why |
|---|---|---|
| A UI test that drives the app (`XCUIApplication`) | XCTest | XCUITest has no other host |
| A performance test (`measure`) | XCTest | no other framework here ships a benchmark API |
| Anything else | the axis value | — |

One target may hold two frameworks at once: `xcodebuild test` runs both and reports them separately.
That is why a test added to an existing file keeps that file's framework.

## XCTest

### Declaration

A test is a method whose name begins with `test`, on a `final class` deriving from `XCTestCase`. The
prefix is how the runner collects it — a method named `methodName_condition_expectedResult()` is
compiled, never run, and the suite is green without it. Keep the convention inside the prefix:

<!-- typecheck -->
```swift
import XCTest

final class CheckoutServiceTests: XCTestCase {
    func test_submit_emptyCart_throwsEmptyCartError() {
        let sut = CheckoutService(repository: FakeOrderRepository())
        XCTAssertThrowsError(try sut.submit(Cart.empty))
    }
}
```

A fresh instance of the class is created for every test method, so stored properties do not leak
between tests; anything static does.

### Assertions

`XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertNil`, `XCTAssertThrowsError`, `XCTFail`. A failed
assertion records and continues, so a test that must not go on unwraps with
`let value = try XCTUnwrap(optional)` and throws. `XCTAssertEqual(_:_:accuracy:)` for floating point.

### Lifecycle

`override func setUp()`, `override func setUpWithError() throws`, `override func setUp() async
throws` and their `tearDown` counterparts, per test method; `override class func setUp()` once per
class. `addTeardownBlock { }` registers cleanup from inside a test.

### Parameterization

None. Either write one method per case, or loop inside a test and label the iterations with
`XCTContext.runActivity(named:)` so a failure says which one broke.

### Async

A test method may be `async throws` and `await` directly. For a callback API, `XCTestExpectation`
plus `await fulfillment(of: [expectation], timeout: 1)`. `@MainActor` on the class where the type
under test is main-actor isolated.

### Failure output

```
/path/to/CheckoutServiceTests.swift:16: error: -[AppTests.CheckoutServiceTests test_submit] : XCTAssertEqual failed: ("1") is not equal to ("2")
Test Case '-[AppTests.CheckoutServiceTests test_submit]' failed (0.081 seconds).
	 Executed 1 test, with 1 failure (0 unexpected) in 0.081 (0.081) seconds
```

The path is absolute, the line has no column, and the test is named `-[Target.Suite method]`.

### Setup

Nothing to add: XCTest ships with the toolchain. The tests live in the Xcode test target, or in
`.testTarget(name:dependencies:)` of `Package.swift`.

## Swift Testing

### Declaration

`import Testing`, then `@Test` on a free function or on a method of a `@Suite` type. The name needs
no prefix — the attribute is what the runner collects — and a readable name goes in the attribute:

<!-- typecheck -->
```swift
import Testing

@Suite("Checkout")
struct CheckoutServiceSuite {
    @Test("submitting an empty cart is rejected")
    func submit_emptyCart_throwsEmptyCartError() {
        let sut = CheckoutService(repository: FakeOrderRepository())
        #expect(throws: CheckoutError.emptyCart) { try sut.submit(Cart.empty) }
    }
}
```

Tests run in parallel by default, including across suites: shared mutable state is a race, not a
flake. `@Suite(.serialized)` turns that off for one suite.

### Assertions

`#expect(condition)` records the failure and lets the test continue; `try #require(condition)` stops
it, and `try #require(optional)` unwraps. `#expect(throws: ErrorType.self) { }` and
`#expect(throws: Never.self) { }` for the throwing and non-throwing cases.

### Lifecycle

A `struct` suite is created fresh for every test, so `init()` is the setup and there is no teardown:
release what you must with `defer` inside the test. A `final class` or `actor` suite may use `deinit`
as teardown.

### Parameterization

`@Test(arguments: [...])` runs one case per element, each reported on its own;
`@Test(arguments: zip(inputs, expected))` pairs them. Prefer it to a loop: a loop reports one failure
for the whole set.

### Async

`@Test func … () async throws` and `await` directly. A callback is confirmed with
`await confirmation("callback fires") { confirmed in … confirmed() }`, which also asserts how many
times it fired. `.timeLimit(.minutes(1))` as a trait, not a per-wait timeout.

### Failure output

```
✘ Test submit_emptyCart_throwsEmptyCartError() recorded an issue at CheckoutServiceTests.swift:6:5: Expectation failed: sut.total == 2
↳ sut.total == 2 → false
↳   sut.total → 1
✘ Test "named case" recorded an issue with 1 argument arg → "b" at CheckoutServiceTests.swift:11:5: Expectation failed: arg == "a"
✘ Test submit_emptyCart_throwsEmptyCartError() failed after 0.001 seconds with 1 issue.
✘ Test run with 2 tests in 0 suites failed after 0.001 seconds with 2 issues.
```

Three things differ from XCTest and decide how a run is read: the file is a basename with a line and
a column, the issue line may begin with a zero-width space before the `✘` (match the mark, never the
start of the line), and none of this appears as `Test Case '…' failed` or in `Executed N tests, with
M failures` — that summary counts XCTest only. A parameterized case names its argument in the line.

### Setup

Nothing to add: the testing library ships with the toolchain (Xcode 16 and later). A target may hold
XCTest and Swift Testing side by side; `xcodebuild test` runs both in one pass.

## Quick+Nimble

### Declaration

A spec is a `final class` deriving from `QuickSpec` with `override class func spec()`; examples are
the `it` closures inside `describe` / `context`, and their names are the strings, not the function
name. `AsyncSpec` is the async-capable base (Quick 7). Per-example state goes in `@TestState`, which
is reset for every example.

```swift
final class CheckoutServiceSpec: QuickSpec {
    override class func spec() {
        @TestState var sut: CheckoutService!

        describe("submit") {
            beforeEach { sut = CheckoutService(repository: FakeOrderRepository()) }

            context("with an empty cart") {
                it("is rejected") {
                    expect { try sut.submit(Cart.empty) }.to(throwError())
                }
            }
        }
    }
}
```

### Assertions

Nimble: `expect(value).to(equal(other))`, `beNil()`, `beTrue()`, `throwError()`,
`beCloseTo(_:within:)`, each negated with `toNot`. `expect { }` takes a throwing closure.

### Lifecycle

`beforeEach` / `afterEach` per example, `beforeSuite` / `afterSuite` per spec run,
`justBeforeEach` for a value that later `context` blocks override. `@TestState` resets on its own.

### Parameterization

A loop around `it(…)` inside the spec — each iteration registers its own example, so give the
iteration's value to the example's name.

### Async

`AsyncSpec` with `await` in the examples. For a condition that becomes true later,
`expect(value).toEventually(equal(other), timeout: .seconds(1))`, which polls instead of waiting once.

### Failure output

Through XCTest's channel, because that is what Quick runs on:

```
/path/to/CheckoutServiceSpec.swift:9: error: -[AppTests.CheckoutServiceSpec submit, with an empty cart, is rejected] : expected to equal <2>, got <1>
```

The test name is the example path — `describe`, `context` and `it` strings joined — and the message
is Nimble's. Nothing extra has to be parsed for this value.

### Setup

Two SPM packages in the test target, `Quick` and `Nimble` (7.6 and 13.8 at the time of writing), or
their Xcode-project equivalents. A project that has neither does not take this value: the axis is
detected from the imports that are there.
