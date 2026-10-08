import Foundation

public struct Draft: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var text: String
    public var modifiedAt: Date

    public init(id: UUID = UUID(), title: String = "", text: String = "", modifiedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.text = text
        self.modifiedAt = modifiedAt
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名草稿" : trimmed
    }

    public var preview: String {
        let first = text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? "还没有内容"
        return String(first.prefix(90))
    }

    public var exportName: String {
        let invalid = CharacterSet(charactersIn: "/\\:\n\r\0")
        let clean = displayTitle.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(80)) + ".txt"
    }
}

public struct Workspace: Codable, Equatable {
    public var version: Int
    public var drafts: [Draft]
    public var selectedID: UUID
    public var fontSize: Double
    public var wrapsLines: Bool
    public var codeMode: Bool

    public init() {
        let draft = Draft()
        version = 1
        drafts = [draft]
        selectedID = draft.id
        fontSize = 16
        wrapsLines = true
        codeMode = false
    }

    public mutating func normalize() throws {
        guard version == 1 else { throw StoreError.unsupportedVersion(version) }
        guard Set(drafts.map(\.id)).count == drafts.count else { throw StoreError.invalidWorkspace }
        if drafts.isEmpty { drafts = [Draft()] }
        if !drafts.contains(where: { $0.id == selectedID }) { selectedID = drafts[0].id }
        fontSize = min(28, max(12, fontSize.isFinite ? fontSize : 16))
    }

    public var selectedIndex: Int { drafts.firstIndex(where: { $0.id == selectedID }) ?? 0 }
}

public enum TextTransform {
    case formatJSON, trimLines, removeBlankLines, uniqueLines

    public func apply(to text: String) throws -> String {
        switch self {
        case .formatJSON:
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self)
        case .trimLines:
            return Self.lines(text).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        case .removeBlankLines:
            return Self.lines(text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        case .uniqueLines:
            var seen = Set<String>()
            return Self.lines(text).filter { seen.insert($0).inserted }.joined(separator: "\n")
        }
    }

    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
    }
}

public struct TextStatistics: Equatable {
    public let characters: Int
    public let lines: Int
    public let cursorLine: Int
    public let cursorColumn: Int

    /// AppKit offsets use UTF-16; visible columns count grapheme clusters.
    public init(text: String, utf16Cursor: Int) {
        characters = text.count
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        lines = normalized.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let nsText = text as NSString
        let prefix = nsText.substring(to: min(max(0, utf16Cursor), nsText.length))
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        cursorLine = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        cursorColumn = (prefix.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0) + 1
    }
}
