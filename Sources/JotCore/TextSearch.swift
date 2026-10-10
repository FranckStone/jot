import Foundation

/// Literal queries; replacement text never interprets regex templates such as $1.
public struct TextSearch {
    private let expression: NSRegularExpression?
    public init(query: String, caseSensitive: Bool = false, wholeWord: Bool = false) {
        guard !query.isEmpty else { expression = nil; return }
        let literal = NSRegularExpression.escapedPattern(for: query)
        let pattern = wholeWord ? "(?<![\\p{L}\\p{N}_])(?:\(literal))(?![\\p{L}\\p{N}_])" : literal
        expression = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
    }
    public func ranges(in text: String) -> [NSRange] {
        guard let expression else { return [] }
        var ranges: [NSRange] = []
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, _ in
            if let match { ranges.append(match.range) }
        }
        return ranges
    }
    public func replacingAll(in text: String, with replacement: String) -> String {
        guard let expression else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }
}

/// Imported text: UTF-8, UTF-16 with a byte order mark, then GB18030, which also covers GBK and GB2312.
public enum TextDecoding {
    public static func decode(_ data: Data) -> String? {
        let decoded: String?
        if let utf8 = String(data: data, encoding: .utf8) { decoded = utf8 }
        else if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) { decoded = String(data: data, encoding: .utf16) }
        else { decoded = String(data: data, encoding: gb18030) }
        guard let decoded else { return nil }
        return decoded.hasPrefix("\u{feff}") ? String(decoded.dropFirst()) : decoded
    }
    private static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
}
