@testable import AppBundle
import Dispatch
import XCTest

final class CompletableFutureTest: XCTestCase {
    func testCompletedValueIsReturned() {
        let future = CompletableFuture<Int>()
        future.complete(42)
        XCTAssertEqual(future.blockingGet(timeout: .now(), fallback: -1), 42)
    }

    func testMissingWindowNilIsACompletedResult() {
        let future = CompletableFuture<Int?>()
        future.complete(nil)
        XCTAssertNil(future.blockingGet(timeout: .now(), fallback: 42))
    }

    func testUnresponsiveOperationReturnsFallback() {
        let future = CompletableFuture<Int>()
        XCTAssertEqual(future.blockingGet(timeout: .now(), fallback: -1), -1)
        future.complete(42)
    }
}
