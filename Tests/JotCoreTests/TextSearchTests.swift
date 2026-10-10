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

    func testDecodingCoversUnicodeAndGB18030() throws {
        let sample = "中文 GBK 文本，含标点。"
        XCTAssertEqual(TextDecoding.decode(Data(sample.utf8)), sample)
        XCTAssertEqual(TextDecoding.decode(Data([0xef, 0xbb, 0xbf]) + Data(sample.utf8)), sample)
        XCTAssertEqual(TextDecoding.decode(try XCTUnwrap(sample.data(using: .utf16))), sample)
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let encoded = try XCTUnwrap(sample.data(using: gbk))
        XCTAssertNil(String(data: encoded, encoding: .utf8), "sample must not also be valid UTF-8")
        XCTAssertEqual(TextDecoding.decode(encoded), sample)
        XCTAssertNil(TextDecoding.decode(Data([0x81, 0x20])), "incomplete GB18030 sequence")
    }
}
