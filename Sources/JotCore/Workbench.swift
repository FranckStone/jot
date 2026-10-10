import Foundation

public enum ItemKind: String, Codable, CaseIterable {
    case text, json, table, pdf, image, file
    public var label: String {
        switch self {
        case .text: return "文本"
        case .json: return "JSON"
        case .table: return "表格"
        case .pdf: return "PDF"
        case .image: return "图片"
        case .file: return "文件"
        }
    }
    public var isText: Bool { self == .text || self == .json || self == .table }
    public static func detect(text: String) -> ItemKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
           (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil { return .json }
        return .text
    }
}

public struct BoardItem: Codable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var kind: ItemKind
    public var text: String
    public var attachment: String?
    public var originalName: String?
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var sourceID: UUID?
    public var operation: String?
    public var modifiedAt: Date

    public init(id: UUID = UUID(), title: String = "未命名文本", kind: ItemKind = .text, text: String = "",
                attachment: String? = nil, originalName: String? = nil, x: Double = 40, y: Double = 40,
                width: Double = 360, height: Double = 320, sourceID: UUID? = nil, operation: String? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.text = text
        self.attachment = attachment; self.originalName = originalName
        self.x = x; self.y = y; self.width = width; self.height = height
        self.sourceID = sourceID; self.operation = operation; modifiedAt = Date()
    }
    public var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名\(kind.label)" : title }
    /// True when a card rendered from `other` would look the same apart from its position and size.
    public func hasSameContent(as other: BoardItem) -> Bool {
        var placed = other
        placed.x = x; placed.y = y; placed.width = width; placed.height = height
        return placed == self
    }
}

public struct Workbench: Codable, Equatable {
    public static let minimumZoom = 0.35
    public static let maximumZoom = 2.0
    public var version = 1
    public var items: [BoardItem] = []
    public var selectedID: UUID?
    public var zoom: Double = 1
    public init() {}
    public init(legacy: Workspace) {
        items = legacy.drafts.enumerated().map { index, draft in
            var item = BoardItem(id: draft.id, title: draft.displayTitle, kind: ItemKind.detect(text: draft.text),
                                 text: draft.text, x: 40 + Double(index % 3) * 400, y: 40 + Double(index / 3) * 360)
            item.modifiedAt = draft.modifiedAt
            return item
        }
        selectedID = legacy.selectedID
    }
    public mutating func normalize() throws {
        guard version == 1 else { throw StoreError.unsupportedVersion(version) }
        guard Set(items.map(\.id)).count == items.count else { throw StoreError.invalidWorkspace }
        for index in items.indices {
            guard items[index].x.isFinite, items[index].y.isFinite,
                  items[index].width.isFinite, items[index].height.isFinite else { throw StoreError.invalidWorkspace }
            if let name = items[index].attachment {
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { throw StoreError.invalidWorkspace }
            }
            items[index].x = min(100_000, max(0, items[index].x))
            items[index].y = min(100_000, max(0, items[index].y))
            items[index].width = min(1600, max(280, items[index].width))
            items[index].height = min(1600, max(220, items[index].height))
        }
        zoom = zoom.isFinite ? min(Self.maximumZoom, max(Self.minimumZoom, zoom)) : 1
        if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id }
    }
}

// Files written by older versions lack fields added later; missing keys fall back to defaults
// instead of making the whole workbench unreadable. Decode every new field with decodeIfPresent.
extension BoardItem {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        kind = try values.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .text
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        attachment = try values.decodeIfPresent(String.self, forKey: .attachment)
        originalName = try values.decodeIfPresent(String.self, forKey: .originalName)
        x = try values.decodeIfPresent(Double.self, forKey: .x) ?? 40
        y = try values.decodeIfPresent(Double.self, forKey: .y) ?? 40
        width = try values.decodeIfPresent(Double.self, forKey: .width) ?? 360
        height = try values.decodeIfPresent(Double.self, forKey: .height) ?? 320
        sourceID = try values.decodeIfPresent(UUID.self, forKey: .sourceID)
        operation = try values.decodeIfPresent(String.self, forKey: .operation)
        // Undo keeps the newer of two edits; an unknown date must never win.
        modifiedAt = try values.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }
}

extension Workbench {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try values.decodeIfPresent([BoardItem].self, forKey: .items) ?? []
        selectedID = try values.decodeIfPresent(UUID.self, forKey: .selectedID)
        zoom = try values.decodeIfPresent(Double.self, forKey: .zoom) ?? 1
    }
}

public struct WorkbenchLoadResult {
    public let workbench: Workbench
    public let warning: String?
    public let canSave: Bool
}

/// A separate store leaves the original drafts intact during migration.
/// After `load()`, call `save` from one serial queue at a time.
public final class WorkbenchStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("workbench.json") }
    public var backupURL: URL { directory.appendingPathComponent("workbench.backup.json") }
    public var attachmentsURL: URL { directory.appendingPathComponent("attachments", isDirectory: true) }
    private var canOverwrite = true
    // Size and date of the file this store last read or wrote, so saves can skip re-validating it.
    private var validFileStamp: [FileAttributeKey: AnyHashable]?
    public init(directory: URL) { self.directory = directory }

    public func load() -> WorkbenchLoadResult {
        let files = FileManager.default
        validFileStamp = nil
        if !files.fileExists(atPath: fileURL.path), !files.fileExists(atPath: backupURL.path) {
            let legacy = DraftStore(directory: directory).load()
            canOverwrite = legacy.canSave
            return .init(workbench: Workbench(legacy: legacy.workspace), warning: legacy.warning, canSave: legacy.canSave)
        }
        do {
            let stamp = fileStamp()
            let workbench = try decode(Data(contentsOf: fileURL))
            validFileStamp = stamp
            return .init(workbench: workbench, warning: nil, canSave: true)
        } catch {
            if case StoreError.unsupportedVersion = error {
                canOverwrite = false
                return .init(workbench: Workbench(), warning: "工作台版本较新，已暂停保存并保留原文件。", canSave: false)
            }
            if let recovered = try? decode(Data(contentsOf: backupURL)) {
                do {
                    if files.fileExists(atPath: fileURL.path) {
                        try files.copyItem(at: fileURL, to: directory.appendingPathComponent("workbench-unreadable-\(UUID().uuidString).json"))
                    }
                    return .init(workbench: recovered, warning: "已从备份恢复工作台，原文件已保留。", canSave: true)
                } catch { }
            }
            canOverwrite = false
            return .init(workbench: Workbench(), warning: "无法读取工作台，已暂停保存。原文件已保留。", canSave: false)
        }
    }

    public func save(_ workbench: Workbench) throws {
        guard canOverwrite else { throw StoreError.unsafeToOverwrite }
        var checked = workbench
        try checked.normalize()
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(checked)
        // Preserve the previous valid snapshot, never a corrupt one. Renaming avoids rereading large files.
        if files.fileExists(atPath: fileURL.path),
           (validFileStamp != nil && fileStamp() == validFileStamp) || (try? decode(Data(contentsOf: fileURL))) != nil {
            if files.fileExists(atPath: backupURL.path) { try files.removeItem(at: backupURL) }
            try files.moveItem(at: fileURL, to: backupURL)
        }
        validFileStamp = nil
        try data.write(to: fileURL, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        validFileStamp = fileStamp()
    }
    private func fileStamp() -> [FileAttributeKey: AnyHashable]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber, let modified = attributes[.modificationDate] as? Date else { return nil }
        return [.size: size, .modificationDate: modified]
    }

    public func copyAttachment(from source: URL) throws -> String {
        guard canOverwrite else { throw StoreError.unsafeToOverwrite }
        let files = FileManager.default
        try files.createDirectory(at: attachmentsURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = UUID().uuidString + (source.pathExtension.isEmpty ? "" : "." + source.pathExtension)
        let destination = attachmentsURL.appendingPathComponent(name)
        try files.copyItem(at: source, to: destination)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return name
    }

    public func saveImageData(_ data: Data) throws -> String {
        guard canOverwrite else { throw StoreError.unsafeToOverwrite }
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let name = UUID().uuidString + ".png"
        let url = attachmentsURL.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return name
    }

    public func attachmentURL(for item: BoardItem) -> URL? {
        guard let name = item.attachment, !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else { return nil }
        return attachmentsURL.appendingPathComponent(name)
    }
    private func decode(_ data: Data) throws -> Workbench {
        var result = try JSONDecoder().decode(Workbench.self, from: data)
        try result.normalize()
        return result
    }
}

public enum TableDataError: LocalizedError {
    case unclosedQuote, tooLarge
    public var errorDescription: String? {
        switch self {
        case .unclosedQuote: return "表格中有未闭合的引号，请先修正原文。"
        case .tooLarge: return "表格超过 20,000 行或 200 列，请拆分后处理。"
        }
    }
}

public struct TableData {
    public var rows: [[String]]
    public init(text: String, delimiter: Character? = nil) throws {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var headerQuoted = false, commas = 0, tabs = 0
        for char in normalized {
            if char == "\"" { headerQuoted.toggle() }
            else if !headerQuoted {
                if char == "\n" { break }
                if char == "," { commas += 1 }
                if char == "\t" { tabs += 1 }
            }
        }
        let separator = delimiter ?? (tabs > commas ? "\t" : ",")
        var result: [[String]] = [], row: [String] = [], field = "", quoted = false, closedQuote = false
        let chars = Array(normalized)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if quoted, index + 1 < chars.count, chars[index + 1] == "\"" { field.append("\""); index += 1 }
                else if quoted { quoted = false; closedQuote = true }
                else if field.isEmpty && !closedQuote { quoted = true }
                else { field.append(char) }
            } else if char == separator && !quoted { row.append(field); field = ""; closedQuote = false }
            else if char == "\n" && !quoted { row.append(field); result.append(row); row = []; field = ""; closedQuote = false }
            else {
                guard !closedQuote else { throw NSError(domain: "Jot.Table", code: 1, userInfo: [NSLocalizedDescriptionKey: "引号结束后只能是分隔符或换行，请检查表格原文。"]) }
                field.append(char)
            }
            guard result.count <= 20_000, row.count <= 200 else { throw TableDataError.tooLarge }
            index += 1
        }
        guard !quoted else { throw TableDataError.unclosedQuote }
        if !field.isEmpty || !row.isEmpty || result.isEmpty || closedQuote { row.append(field); result.append(row) }
        guard result.count <= 20_000, result.allSatisfy({ $0.count <= 200 }) else { throw TableDataError.tooLarge }
        rows = result
    }
    public var csv: String {
        rows.map { row in row.map { field in
            (field.isEmpty && row.count == 1) || field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : field
        }.joined(separator: ",") }.joined(separator: "\n")
    }
    public func json() throws -> String {
        guard let header = rows.first else { return "[]" }
        guard Set(header).count == header.count, !header.contains("") else {
            throw NSError(domain: "Jot", code: 1, userInfo: [NSLocalizedDescriptionKey: "首行必须是非空且不重复的列名。"])
        }
        guard rows.dropFirst().allSatisfy({ $0.count == header.count }) else {
            throw NSError(domain: "Jot", code: 2, userInfo: [NSLocalizedDescriptionKey: "各行列数不一致，请先修正原文。"])
        }
        let objects = rows.dropFirst().map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
        return String(decoding: try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
}
