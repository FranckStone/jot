import XCTest
@testable import JotCore

final class WorkbenchTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("jot-board-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testMigrationKeepsOriginalDraftFileAndUnicodeContent() throws {
        let legacyStore = DraftStore(directory: directory)
        var legacy = Workspace()
        legacy.drafts = [Draft(title: "资料", text: "你好👋"), Draft(title: "接口", text: "{\"ok\":true}")]
        legacy.selectedID = legacy.drafts[1].id
        try legacyStore.save(legacy)
        let original = try Data(contentsOf: legacyStore.fileURL)
        let store = WorkbenchStore(directory: directory)
        let loaded = store.load()
        XCTAssertTrue(loaded.canSave)
        XCTAssertEqual(loaded.workbench.items.map(\.text), legacy.drafts.map(\.text))
        XCTAssertEqual(loaded.workbench.items[1].kind, .json)
        XCTAssertEqual(loaded.workbench.selectedID, legacy.selectedID)
        try store.save(loaded.workbench)
        XCTAssertEqual(try Data(contentsOf: legacyStore.fileURL), original)
        XCTAssertEqual(store.load().workbench, loaded.workbench)
    }

    func testBoardRoundTripRetainsGeometryAttachmentsAndProvenance() throws {
        let source = directory.appendingPathComponent("original.pdf")
        let content = Data("test attachment".utf8)
        try content.write(to: source)
        let store = WorkbenchStore(directory: directory)
        let name = try store.copyAttachment(from: source)
        var board = Workbench()
        let item = BoardItem(title: "文档", kind: .pdf, attachment: name, originalName: "original.pdf", x: 132, y: 245, width: 560, height: 480)
        let output = BoardItem(title: "文档 · 提取文字", text: "内容", sourceID: item.id, operation: "提取文字")
        board.items = [item, output]; board.selectedID = output.id; board.zoom = 0.65
        try store.save(board)
        XCTAssertEqual(store.load().workbench, board)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.attachmentURL(for: item))), content)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testInvalidAttachmentAndDuplicateIDsAreRejected() throws {
        var board = Workbench()
        board.items = [BoardItem(attachment: "../outside.pdf")]
        XCTAssertThrowsError(try board.normalize())
        XCTAssertNil(WorkbenchStore(directory: directory).attachmentURL(for: board.items[0]))
        board.items = [BoardItem()]; board.items.append(board.items[0])
        XCTAssertThrowsError(try board.normalize())
    }

    func testCorruptBoardRecoveryPreservesCorruptOriginal() throws {
        let store = WorkbenchStore(directory: directory)
        var board = Workbench(); board.items = [BoardItem(text: "first")]
        try store.save(board)
        board.items[0].text = "second"; try store.save(board)
        let broken = Data("corrupt".utf8); try broken.write(to: store.fileURL)
        let loaded = store.load()
        XCTAssertTrue(loaded.canSave); XCTAssertNotNil(loaded.warning)
        XCTAssertEqual(loaded.workbench.items.first?.text, "first")
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("workbench-unreadable-") }
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved)), broken)
    }

    func testBackupHoldsPreviousSaveAndNeverACorruptFile() throws {
        let store = WorkbenchStore(directory: directory)
        var board = Workbench(); board.items = [BoardItem(text: "first")]
        try store.save(board)
        board.items[0].text = "second"; try store.save(board)
        let backup = try JSONDecoder().decode(Workbench.self, from: Data(contentsOf: store.backupURL))
        XCTAssertEqual(backup.items.first?.text, "first")
        let permissions = try FileManager.default.attributesOfItem(atPath: store.backupURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        // Replaced behind the store's back, the file must be revalidated before it becomes the backup.
        try Data("corrupt-but-longer-than-before".utf8).write(to: store.fileURL)
        board.items[0].text = "third"; try store.save(board)
        let kept = try JSONDecoder().decode(Workbench.self, from: Data(contentsOf: store.backupURL))
        XCTAssertEqual(kept.items.first?.text, "first")
        XCTAssertEqual(store.load().workbench.items.first?.text, "third")
    }

    func testSavesFromBackgroundQueueLeaveLatestBoard() throws {
        let store = WorkbenchStore(directory: directory)
        _ = store.load()
        let queue = DispatchQueue(label: "test.save")
        var board = Workbench(); board.items = [BoardItem(text: "")]
        for index in 0..<20 {
            board.items[0].text = String(repeating: "数据", count: 1000) + "\(index)"
            let snapshot = board
            queue.async { try? store.save(snapshot) }
        }
        queue.sync {}
        XCTAssertEqual(store.load().workbench.items.map(\.text), board.items.map(\.text))
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let id = UUID()
        let data = Data(#"{"version":1,"items":[{"id":"\#(id.uuidString)","text":"旧数据","futureField":true}]}"#.utf8)
        try data.write(to: WorkbenchStore(directory: directory).fileURL)
        let loaded = WorkbenchStore(directory: directory).load()
        XCTAssertTrue(loaded.canSave); XCTAssertNil(loaded.warning)
        let item = try XCTUnwrap(loaded.workbench.items.first)
        XCTAssertEqual(item.id, id); XCTAssertEqual(item.text, "旧数据")
        XCTAssertEqual(item.kind, .text); XCTAssertEqual(item.displayTitle, "未命名文本")
        XCTAssertEqual(NSRect(x: item.x, y: item.y, width: item.width, height: item.height), NSRect(x: 40, y: 40, width: 360, height: 320))
        XCTAssertEqual(item.modifiedAt, .distantPast)
        XCTAssertEqual(loaded.workbench.zoom, 1); XCTAssertEqual(loaded.workbench.selectedID, id)
        // A card without an id cannot be restored safely, so the file is still rejected.
        try Data(#"{"version":1,"items":[{"text":"x"}]}"#.utf8).write(to: WorkbenchStore(directory: directory).fileURL)
        XCTAssertFalse(WorkbenchStore(directory: directory).load().canSave)
    }

    func testSameContentIgnoresOnlyGeometry() {
        let item = BoardItem(title: "卡片", text: "内容", x: 10, y: 20)
        var moved = item; moved.x = 400; moved.y = 300; moved.width = 600; moved.height = 500
        XCTAssertTrue(item.hasSameContent(as: moved))
        var edited = moved; edited.text = "新内容"
        XCTAssertFalse(item.hasSameContent(as: edited))
        var renamed = item; renamed.title = "改名"
        XCTAssertFalse(item.hasSameContent(as: renamed))
    }

    func testUnsupportedVersionDoesNotFallBackAndOverwrite() throws {
        let store = WorkbenchStore(directory: directory)
        try store.save(Workbench()); try store.save(Workbench())
        var future = Workbench(); future.version = 2
        let data = try JSONEncoder().encode(future); try data.write(to: store.fileURL)
        XCTAssertFalse(store.load().canSave)
        XCTAssertThrowsError(try store.save(Workbench()))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), data)
    }

    func testCSVQuotedFieldsNewlinesAndEscapedQuotesRoundTrip() throws {
        let csv = "名称,备注,空值\r\n甲,\"一行\n二行,含逗号\",\r\n乙,\"他说\"\"你好\"\"\",x"
        let table = try TableData(text: csv)
        XCTAssertEqual(table.rows[1], ["甲", "一行\n二行,含逗号", ""])
        XCTAssertEqual(table.rows[2], ["乙", "他说\"你好\"", "x"])
        XCTAssertEqual(try TableData(text: table.csv).rows, table.rows)
        let objects = try JSONSerialization.jsonObject(with: Data(table.json().utf8)) as? [[String: String]]
        XCTAssertEqual(objects?.count, 2)
        XCTAssertEqual(objects?[0]["备注"], "一行\n二行,含逗号")
    }

    func testTSVAndInvalidTables() throws {
        XCTAssertEqual(try TableData(text: "a\tb\n1\t2\n").rows, [["a", "b"], ["1", "2"]])
        XCTAssertThrowsError(try TableData(text: "a,b\n\"broken"))
        XCTAssertThrowsError(try TableData(text: "a,a\n1,2").json())
        XCTAssertThrowsError(try TableData(text: "a,b\n1,2,3").json())
        XCTAssertEqual(try TableData(text: "a,b\n1,\"a\tb\"").rows, [["a", "b"], ["1", "a\tb"]])
        XCTAssertThrowsError(try TableData(text: "a,b\n1,\"value\"suffix"))
        XCTAssertEqual(try TableData(text: "name\n\"\"").rows, [["name"], [""]])
        let emptyLastRow = try TableData(text: "name\n\"\"")
        XCTAssertEqual(try TableData(text: emptyLastRow.csv).rows, emptyLastRow.rows)
    }
}
