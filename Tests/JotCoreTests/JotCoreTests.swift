import XCTest
@testable import JotCore

final class JotCoreTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("jot-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testWorkspaceRoundTripAndSelection() throws {
        let store = DraftStore(directory: directory)
        var workspace = Workspace()
        let draft = Draft(title: "中文草稿", text: "你好 👨‍👩‍👧‍👦\n{\"ok\":true}")
        workspace.drafts.append(draft)
        workspace.selectedID = draft.id
        workspace.fontSize = 19
        workspace.codeMode = true
        try store.save(workspace)
        XCTAssertEqual(store.load().workspace, workspace)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testRecoveryPreservesCorruptFileAndValidBackup() throws {
        let store = DraftStore(directory: directory)
        var workspace = Workspace()
        workspace.drafts[0].text = "previous valid content"
        try store.save(workspace)
        workspace.drafts[0].text = "new content"
        try store.save(workspace)
        let corrupt = Data("broken json".utf8)
        try corrupt.write(to: store.fileURL)
        let result = store.load()
        XCTAssertTrue(result.canSave)
        XCTAssertNotNil(result.warning)
        XCTAssertEqual(result.workspace.drafts[0].text, "previous valid content")
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("drafts-unreadable-") }
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved)), corrupt)
        try store.save(result.workspace)
        XCTAssertEqual(store.load().workspace, result.workspace)
    }

    func testCorruptionWithoutBackupRefusesOverwrite() throws {
        let store = DraftStore(directory: directory)
        let corrupt = Data("not a workspace".utf8)
        try corrupt.write(to: store.fileURL)
        XCTAssertFalse(store.load().canSave)
        XCTAssertThrowsError(try store.save(Workspace()))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }

    func testFutureVersionIsNeverDowngraded() throws {
        let store = DraftStore(directory: directory)
        try store.save(Workspace())
        try store.save(Workspace())
        var future = Workspace()
        future.version = 99
        let data = try JSONEncoder().encode(future)
        try data.write(to: store.fileURL)
        XCTAssertFalse(store.load().canSave)
        XCTAssertThrowsError(try store.save(Workspace()))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), data)
    }

    func testMissingPrimaryRecoversBackup() throws {
        let store = DraftStore(directory: directory)
        var workspace = Workspace()
        workspace.drafts[0].text = "recover me"
        try store.save(workspace)
        try store.save(workspace)
        try FileManager.default.removeItem(at: store.fileURL)
        XCTAssertEqual(store.load().workspace.drafts[0].text, "recover me")
    }

    func testMissingPrimaryWithCorruptBackupStopsSaving() throws {
        let store = DraftStore(directory: directory)
        let corrupt = Data("unreadable backup".utf8)
        try corrupt.write(to: store.backupURL)
        XCTAssertFalse(store.load().canSave)
        XCTAssertThrowsError(try store.save(Workspace()))
        XCTAssertEqual(try Data(contentsOf: store.backupURL), corrupt)
    }

    func testUnicodeCountsAndUTF16Cursor() {
        let text = "你好👨‍👩‍👧‍👦\r\n第二行\n"
        let cursor = ("你好👨‍👩‍👧‍👦\r\n第" as NSString).length
        let stats = TextStatistics(text: text, utf16Cursor: cursor)
        XCTAssertEqual(stats.lines, 3)
        XCTAssertEqual(stats.cursorLine, 2)
        XCTAssertEqual(stats.cursorColumn, 2)
        XCTAssertEqual(stats.characters, text.count)
        XCTAssertEqual(TextStatistics(text: "", utf16Cursor: 0).lines, 1)
    }

    func testTransformsHandleChineseAndWindowsLineEndings() throws {
        XCTAssertEqual(try TextTransform.trimLines.apply(to: "  你好 \r\n\t世界\t"), "你好\n世界")
        XCTAssertEqual(try TextTransform.removeBlankLines.apply(to: "a\r\n \r\nb\r\n"), "a\nb")
        XCTAssertEqual(try TextTransform.uniqueLines.apply(to: "甲\n乙\n甲\n"), "甲\n乙\n")
        let output = try TextTransform.formatJSON.apply(to: "{\"z\":2,\"a\":\"中文\"}")
        XCTAssertTrue(output.contains("\n"))
        let object = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        XCTAssertEqual(object?["a"] as? String, "中文")
        XCTAssertEqual(try TextTransform.formatJSON.apply(to: "42"), "42")
        XCTAssertThrowsError(try TextTransform.formatJSON.apply(to: "{broken}"))
    }

    func testEmptyWorkspaceAndStaleSelectionNormalize() throws {
        var workspace = Workspace()
        workspace.drafts = []
        workspace.fontSize = 300
        try workspace.normalize()
        XCTAssertEqual(workspace.drafts.count, 1)
        XCTAssertEqual(workspace.selectedID, workspace.drafts[0].id)
        XCTAssertEqual(workspace.fontSize, 28)
        workspace.drafts.append(workspace.drafts[0])
        XCTAssertThrowsError(try workspace.normalize())
    }
}
