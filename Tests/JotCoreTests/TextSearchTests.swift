import XCTest
@testable import JotCore

final class TextSearchTests: XCTestCase {
    func testUnicodeRangesAndLiteralReplacement() {
        let text = "🙂你好 / 你好"
        let search = TextSearch(query: "你好")
        XCTAssertEqual(search.ranges(in: text), [NSRange(location: 2, length: 2), NSRange(location: 7, length: 2)])
        XCTAssertEqual(search.replacingAll(in: text, with: "$1\\x"), "🙂$1\\x / $1\\x")
    }
    func testCaseAndWholeWord() {
        XCTAssertEqual(TextSearch(query: "cat").ranges(in: "Cat cat catch").count, 3)
        XCTAssertEqual(TextSearch(query: "cat", caseSensitive: true, wholeWord: true).ranges(in: "Cat cat catch _cat cat2").count, 1)
        XCTAssertEqual(TextSearch(query: "a.b").ranges(in: "a.b axb").count, 1)
    }
    func testEmptyAndDeletionAndNonoverlap() {
        XCTAssertTrue(TextSearch(query: "").ranges(in: "hello").isEmpty)
        XCTAssertEqual(TextSearch(query: "").replacingAll(in: "hello", with: "x"), "hello")
        XCTAssertEqual(TextSearch(query: "aa").replacingAll(in: "aaaaa", with: ""), "a")
    }
}
