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
