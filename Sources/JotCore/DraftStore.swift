import Foundation

public enum StoreError: LocalizedError {
    case unsupportedVersion(Int), invalidWorkspace, unsafeToOverwrite

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "草稿文件版本 \(version) 暂不受支持。原文件已保留。"
        case .invalidWorkspace: return "草稿文件结构异常。原文件已保留。"
        case .unsafeToOverwrite: return "无法读取原草稿文件，已停止自动保存以保护原文件。请先导出当前内容。"
        }
    }
}

public struct LoadResult {
    public var workspace: Workspace
    public var warning: String?
    public var canSave: Bool
}

public final class DraftStore {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("drafts.json") }
    public var backupURL: URL { directory.appendingPathComponent("drafts.backup.json") }
    private var canOverwrite = true

    public init(directory: URL) { self.directory = directory }

    public static func defaultDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["JOT_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jot", isDirectory: true)
    }

    public func load() -> LoadResult {
        let files = FileManager.default
        guard files.fileExists(atPath: fileURL.path) else {
            if files.fileExists(atPath: backupURL.path) {
                if let recovered = try? decode(Data(contentsOf: backupURL)) {
                    return LoadResult(workspace: recovered, warning: "已从本机备份恢复草稿。", canSave: true)
                }
                canOverwrite = false
                return LoadResult(workspace: Workspace(), warning: StoreError.unsafeToOverwrite.localizedDescription, canSave: false)
            }
            return LoadResult(workspace: Workspace(), warning: nil, canSave: true)
        }
        do {
            return LoadResult(workspace: try decode(Data(contentsOf: fileURL)), warning: nil, canSave: true)
        } catch {
            if case StoreError.unsupportedVersion = error {
                canOverwrite = false
                return LoadResult(workspace: Workspace(), warning: error.localizedDescription, canSave: false)
            }
            if let recovered = try? decode(Data(contentsOf: backupURL)) {
                do {
                    let preserved = directory.appendingPathComponent("drafts-unreadable-\(UUID().uuidString).json")
                    try files.copyItem(at: fileURL, to: preserved)
                    return LoadResult(workspace: recovered, warning: "已从本机备份恢复草稿，异常原文件已单独保留。", canSave: true)
                } catch { canOverwrite = false }
            } else { canOverwrite = false }
            return LoadResult(workspace: Workspace(), warning: StoreError.unsafeToOverwrite.localizedDescription, canSave: false)
        }
    }

    public func save(_ workspace: Workspace) throws {
        guard canOverwrite else { throw StoreError.unsafeToOverwrite }
        var checked = workspace
        try checked.normalize()
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(checked)
        // Preserve the previous valid snapshot, never a corrupt one.
        if files.fileExists(atPath: fileURL.path) {
            let previous = try Data(contentsOf: fileURL)
            if (try? decode(previous)) != nil { try previous.write(to: backupURL, options: .atomic) }
        }
        try data.write(to: fileURL, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        if files.fileExists(atPath: backupURL.path) {
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }
    }

    private func decode(_ data: Data) throws -> Workspace {
        var result = try JSONDecoder().decode(Workspace.self, from: data)
        try result.normalize()
        return result
    }
}
