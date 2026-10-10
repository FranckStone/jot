import AppKit
import PDFKit
import Quartz
import JotCore

extension ItemKind {
    var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .json: return "curlybraces"
        case .table: return "tablecells"
        case .pdf: return "doc.richtext"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}

final class WorkbenchCanvas: NSView {
    var onDrop: ((NSPasteboard, NSPoint) -> Bool)?
    var onClearSelection: (() -> Void)?
    var onPaste: (() -> Void)?
    var hasItems = true { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .string, .png, .tiff])
        setAccessibilityLabel("自由画布")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        Palette.backdrop.setFill(); dirtyRect.fill()
        if !hasItems {
            let title = "把文件放上来，开始处理。"
            title.draw(at: NSPoint(x: 56, y: 64), withAttributes: [.font: NSFont.systemFont(ofSize: 25, weight: .medium), .foregroundColor: Palette.ink])
            "拖入 PDF、图片、表格或任意文件，也可以直接粘贴文字。\n每份内容成为一张卡片，拖动排列，双击专注查看。".draw(
                in: NSRect(x: 56, y: 110, width: 650, height: 70),
                withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: Palette.muted])
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); onClearSelection?()
    }
    @objc func paste(_ sender: Any?) { onPaste?() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard, convert(sender.draggingLocation, from: nil)) ?? false
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

final class CardHandle: NSView {
    var onStart: ((NSEvent) -> Void)?
    var onDrag: ((NSEvent) -> Void)?
    var onEnd: (() -> Void)?
    var resize = false
    override func mouseDown(with event: NSEvent) { onStart?(event) }
    override func mouseDragged(with event: NSEvent) { onDrag?(event) }
    override func mouseUp(with event: NSEvent) { onEnd?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: resize ? .crosshair : .openHand) }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }
    override func draw(_ dirtyRect: NSRect) {
        guard resize else { return }
        Palette.muted.withAlphaComponent(0.6).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: .init(x: 5, y: 5)); path.line(to: .init(x: 13, y: 13))
        path.move(to: .init(x: 10, y: 5)); path.line(to: .init(x: 13, y: 8)); path.stroke()
    }
}

final class BoardCardView: NSView {
    let itemID: UUID
    /// The item this card was built from; geometry may since have changed by dragging.
    let item: BoardItem
    let titleLabel: NSTextField
    private let footerLabel: NSTextField
    private let preview: NSView
    private let header = CardHandle()
    private let grip = CardHandle()
    var onSelect: ((UUID) -> Void)?
    var onOpen: ((UUID) -> Void)?
    var onDuplicate: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    private var deleteButton: NSButton?
    var isProcessing = false { didSet { deleteButton?.isEnabled = !isProcessing } }
    var onFrameChange: ((UUID, NSRect) -> Void)?
    private var startingFrame = NSRect.zero
    private var startingPoint = NSPoint.zero
    var selected = false { didSet { refreshColors() } }

    init(item: BoardItem, url: URL?) {
        itemID = item.id; self.item = item
        titleLabel = label(item.displayTitle, size: 13, weight: .semibold)
        footerLabel = label(item.operation.map { "来自处理 · \($0)" } ?? (item.kind.isText ? "\(item.text.count) 字符 · 双击标题编辑" : "\(item.kind.label) · 双击标题展开"), size: 10, color: Palette.muted)
        preview = makeItemPreview(item: item, url: url, compact: true)
        super.init(frame: NSRect(x: item.x, y: item.y, width: item.width, height: item.height))
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(item.kind.label)卡片：\(item.displayTitle)")
        let typeIcon = NSImageView(image: symbol(item.kind.symbolName, size: 14) ?? NSImage())
        typeIcon.contentTintColor = Palette.muted
        let typeName = label(item.kind.label, size: 10, weight: .medium, color: Palette.muted)
        typeName.setContentCompressionResistancePriority(.required, for: .horizontal)
        func cardAction(_ name: String, title: String, action: Selector) -> NSButton {
            let control = FeedbackButton(image: symbol(name, size: 12) ?? NSImage(), target: self, action: action)
            control.compact = true; control.imagePosition = .imageOnly; control.imageScaling = .scaleProportionallyDown
            control.toolTip = title; control.setAccessibilityLabel("\(title) \(item.displayTitle)")
            control.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([control.widthAnchor.constraint(equalToConstant: 28), control.heightAnchor.constraint(equalToConstant: 28)])
            return control
        }
        let duplicate = cardAction("doc.on.doc", title: "复制卡片", action: #selector(duplicateCard))
        let remove = cardAction("trash", title: "删除卡片（⌘Z 可撤销）", action: #selector(deleteCard))
        deleteButton = remove
        let open = cardAction("arrow.up.left.and.arrow.down.right", title: item.kind.isText ? "展开编辑" : "展开预览", action: #selector(openCard))
        let actions = NSStackView(views: [duplicate, remove, open]); actions.spacing = 6
        [header, preview, footerLabel, grip, actions].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        [typeIcon, titleLabel, typeName].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; header.addSubview($0) }
        grip.resize = true
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor), header.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -10),
            header.topAnchor.constraint(equalTo: topAnchor), header.heightAnchor.constraint(equalToConstant: 48),
            typeIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16), typeIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            typeIcon.widthAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: typeIcon.trailingAnchor, constant: 8), titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: typeName.leadingAnchor, constant: -8),
            typeName.trailingAnchor.constraint(equalTo: header.trailingAnchor), typeName.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), actions.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 48), preview.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -34),
            footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            footerLabel.trailingAnchor.constraint(lessThanOrEqualTo: grip.leadingAnchor, constant: -6),
            grip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5), grip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            grip.widthAnchor.constraint(equalToConstant: 20), grip.heightAnchor.constraint(equalToConstant: 20)
        ])
        header.onStart = { [weak self] event in
            guard let self else { return }
            self.onSelect?(self.itemID)
            if event.clickCount == 2 { self.onOpen?(self.itemID); return }
            self.startingFrame = self.frame; self.startingPoint = self.superview?.convert(event.locationInWindow, from: nil) ?? .zero
        }
        header.onDrag = { [weak self] event in
            guard let self, let parent = self.superview else { return }
            let point = parent.convert(event.locationInWindow, from: nil)
            self.setFrameOrigin(NSPoint(x: max(0, self.startingFrame.minX + point.x - self.startingPoint.x), y: max(0, self.startingFrame.minY + point.y - self.startingPoint.y)))
        }
        header.onEnd = { [weak self] in guard let self else { return }; self.onFrameChange?(self.itemID, self.frame) }
        grip.onStart = { [weak self] event in
            guard let self else { return }; self.onSelect?(self.itemID)
            self.startingFrame = self.frame; self.startingPoint = self.superview?.convert(event.locationInWindow, from: nil) ?? .zero
        }
        grip.onDrag = { [weak self] event in
            guard let self, let parent = self.superview else { return }
            let point = parent.convert(event.locationInWindow, from: nil)
            self.setFrameSize(NSSize(width: min(1600, max(280, self.startingFrame.width + point.x - self.startingPoint.x)), height: min(1600, max(220, self.startingFrame.height + point.y - self.startingPoint.y))))
        }
        grip.onEnd = header.onEnd
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openCard() { onSelect?(itemID); onOpen?(itemID) }
    @objc private func duplicateCard() { onDuplicate?(itemID) }
    @objc private func deleteCard() { onDelete?(itemID) }
    override func mouseDown(with event: NSEvent) { onSelect?(itemID); if event.clickCount == 2 { onOpen?(itemID) } }
    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Palette.paper.cgColor
            layer?.borderColor = (selected ? Palette.accent : Palette.line).cgColor
            layer?.borderWidth = selected ? 2 : 1
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }
}

final class TablePreview: NSScrollView, NSTableViewDataSource {
    private let rows: [[String]]
    init(data: TableData) {
        rows = Array(data.rows.dropFirst())
        super.init(frame: .zero)
        let table = NSTableView()
        let header = data.rows.first ?? []
        for index in 0..<(data.rows.map(\.count).max() ?? 0) {
            let name = header.indices.contains(index) ? header[index] : ""
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(index)))
            column.title = name.isEmpty ? "列 \(index + 1)" : name
            column.width = 130; column.minWidth = 60
            column.isEditable = false
            table.addTableColumn(column)
        }
        table.dataSource = self; table.rowHeight = 25
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        documentView = table; hasVerticalScroller = true; hasHorizontalScroller = true
        autohidesScrollers = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let column = tableColumn, let index = Int(column.identifier.rawValue), rows[row].indices.contains(index) else { return "" }
        return rows[row][index]
    }
}

private final class WrappingPreviewTextView: NSTextView {
    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        // In a magnified canvas, AppKit's autoresizing deltas include pixel-rounding
        // offsets as the card moves. Use the viewport's absolute width instead.
        if let clip = superview as? NSClipView {
            size.width = clip.bounds.width
        }
        super.setFrameSize(size)
    }
}

func makeItemPreview(item: BoardItem, url: URL?, compact: Bool) -> NSView {
    if item.kind == .table, let data = try? TableData(text: item.text) { return TablePreview(data: data) }
    if item.kind.isText {
        let scroll = NSScrollView()
        let text = WrappingPreviewTextView()
        text.isEditable = false; text.isRichText = false
        text.string = compact ? String(item.text.prefix(12_000)) : item.text
        text.font = item.kind == .json ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
        text.textColor = Palette.ink; text.backgroundColor = Palette.paper
        text.textContainerInset = NSSize(width: 6, height: 8)
        text.isHorizontallyResizable = false
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        return scroll
    }
    if item.kind == .pdf, let url, let document = PDFDocument(url: url) {
        let pdf = PDFView()
        pdf.document = document; pdf.autoScales = true
        pdf.displayMode = compact ? .singlePage : .singlePageContinuous
        pdf.backgroundColor = Palette.paper
        return pdf
    }
    if item.kind == .image, let url, let image = NSImage(contentsOf: url) {
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel(item.displayTitle)
        return view
    }
    if !compact, let url, FileManager.default.fileExists(atPath: url.path), let view = QLPreviewView(frame: .zero, style: .normal) {
        view.previewItem = url as NSURL
        view.autostarts = false
        return view
    }
    let image = NSImageView(image: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? (symbol("doc", size: 48) ?? NSImage()))
    image.imageScaling = .scaleProportionallyDown
    image.translatesAutoresizingMaskIntoConstraints = false
    image.heightAnchor.constraint(equalToConstant: 64).isActive = true
    let missing = url.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true
    let name = label(item.originalName ?? item.displayTitle, size: 12)
    let hint = label(missing ? "附件不可用，请重新导入" : "双击标题使用系统预览", size: 11, color: Palette.muted)
    let stack = NSStackView(views: [image, name, hint])
    stack.orientation = .vertical; stack.spacing = 14; stack.alignment = .centerX
    let container = NSView()
    stack.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(stack)
    NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: container.centerXAnchor), stack.centerYAnchor.constraint(equalTo: container.centerYAnchor), stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -20)])
    return container
}

private final class DetailTextView: NSTextView {
    var dismissFind: (() -> Bool)?
    override func cancelOperation(_ sender: Any?) {
        if dismissFind?() == true { return }
        super.cancelOperation(sender)
    }
}

/// Text display preferences shared by every focus window.
struct EditorSettings {
    var fontSize: CGFloat
    var codeMode: Bool
    var wraps: Bool

    static func load() -> EditorSettings {
        let defaults = UserDefaults.standard
        let size = defaults.object(forKey: "Jot.EditorFontSize") as? Double ?? 15
        return EditorSettings(fontSize: min(28, max(12, size.isFinite ? size : 15)),
                              codeMode: defaults.bool(forKey: "Jot.EditorCodeMode"),
                              wraps: defaults.object(forKey: "Jot.EditorWraps") as? Bool ?? true)
    }
    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Double(fontSize), forKey: "Jot.EditorFontSize")
        defaults.set(codeMode, forKey: "Jot.EditorCodeMode")
        defaults.set(wraps, forKey: "Jot.EditorWraps")
    }
    /// JSON and tables always use monospace, one size smaller to match the proportional body text.
    func font(for kind: ItemKind) -> NSFont {
        codeMode || kind != .text ? .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular) : .systemFont(ofSize: fontSize)
    }
}

final class ItemDetailController: NSWindowController, NSTextViewDelegate, NSTextFieldDelegate {
    let itemID: UUID
    var onChange: ((String, String) -> Void)?
    var onClose: (() -> Void)?
    private let titleField = NSTextField()
    private let editor = DetailTextView()
    private lazy var findBar = FindReplaceBar(editor: editor)
    private let content = NSView()
    private var mode: NSSegmentedControl?
    private let initial: BoardItem
    private var settings: EditorSettings

    init(item: BoardItem, url: URL?, settings: EditorSettings) {
        itemID = item.id; initial = item; self.settings = settings
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = item.displayTitle; window.minSize = NSSize(width: 560, height: 400)
        configureWindowChrome(window, identifier: "Jot.DetailChrome")
        window.isReleasedWhenClosed = false; window.center()
        super.init(window: window)
        let root = SurfaceView(Palette.paper); window.contentView = root
        titleField.stringValue = item.displayTitle; titleField.font = .systemFont(ofSize: 19, weight: .semibold)
        titleField.isBordered = false; titleField.drawsBackground = false; titleField.delegate = self
        titleField.setAccessibilityLabel("卡片名称")
        titleField.textColor = Palette.ink; titleField.cell?.isScrollable = true
        let titleInput = TextInputSurface(field: titleField, showsRestingBorder: false)
        titleField.translatesAutoresizingMaskIntoConstraints = false; titleInput.addSubview(titleField)
        let caption = label(item.kind.isText ? "自动保存 · ⌘F 查找替换" : "\(item.kind.label) · 本机副本", size: 11, color: Palette.muted)
        [titleInput, caption, content].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            titleInput.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14), titleInput.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -210), titleInput.topAnchor.constraint(equalTo: root.topAnchor, constant: 12), titleInput.heightAnchor.constraint(equalToConstant: 38),
            titleField.leadingAnchor.constraint(equalTo: titleInput.leadingAnchor, constant: 10), titleField.trailingAnchor.constraint(equalTo: titleInput.trailingAnchor, constant: -10), titleField.centerYAnchor.constraint(equalTo: titleInput.centerYAnchor),
            caption.leadingAnchor.constraint(equalTo: titleField.leadingAnchor), caption.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 8),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 82), content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16), content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])
        if item.kind.isText {
            editor.string = item.text; editor.isRichText = false; editor.allowsUndo = true
            editor.font = settings.font(for: item.kind)
            editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            editor.textColor = Palette.ink; editor.backgroundColor = Palette.paper
            editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
            editor.textContainerInset = NSSize(width: 16, height: 14)
            editor.isVerticallyResizable = true; editor.autoresizingMask = [.width]
            editor.textContainer?.widthTracksTextView = true; editor.usesFindBar = false
            editor.delegate = self
            findBar.isHidden = true
            findBar.onClose = { [weak self] in self?.findBar.isHidden = true }
            editor.dismissFind = { [weak self] in
                guard let self, !self.findBar.isHidden else { return false }
                self.findBar.dismiss(); return true
            }
            let findButton = button("查找替换", symbol: "magnifyingglass", target: self, action: #selector(showFindBar))
            root.addSubview(findButton)
            NSLayoutConstraint.activate([findButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), findButton.centerYAnchor.constraint(equalTo: titleField.centerYAnchor)])
            if item.kind == .table {
                let control = NSSegmentedControl(labels: ["表格", "原文"], trackingMode: .selectOne, target: self, action: #selector(switchMode))
                control.selectedSegment = 0; mode = control
                control.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(control)
                NSLayoutConstraint.activate([control.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), control.centerYAnchor.constraint(equalTo: caption.centerYAnchor)])
                showTable()
            } else { showEditor() }
        } else { install(makeItemPreview(item: item, url: url, compact: false)) }
        NotificationCenter.default.addObserver(self, selector: #selector(willClose), name: NSWindow.willCloseNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    private func install(_ view: NSView) {
        content.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor), view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.topAnchor.constraint(equalTo: content.topAnchor), view.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        content.layoutSubtreeIfNeeded()
    }
    private func showEditor() {
        if let scroll = editor.enclosingScrollView, scroll.isDescendant(of: content) { return }
        let scroll = NSScrollView(); scroll.documentView = editor
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        let stack = NSStackView(views: [findBar, scroll]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8; stack.detachesHiddenViews = true
        findBar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        install(stack); stack.layoutSubtreeIfNeeded(); editor.frame.size.width = scroll.contentSize.width
        apply(settings); window?.makeFirstResponder(editor)
    }
    func apply(_ settings: EditorSettings) {
        self.settings = settings
        guard initial.kind.isText else { return }
        editor.font = settings.font(for: initial.kind)
        let width = editor.enclosingScrollView?.contentSize.width ?? editor.frame.width
        editor.isHorizontallyResizable = !settings.wraps; editor.autoresizingMask = settings.wraps ? [.width] : []
        editor.textContainer?.widthTracksTextView = settings.wraps
        editor.textContainer?.containerSize = NSSize(width: settings.wraps ? width : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if settings.wraps { editor.setFrameSize(NSSize(width: width, height: editor.frame.height)) }
        editor.enclosingScrollView?.hasHorizontalScroller = !settings.wraps
    }
    private func revealEditor() {
        guard initial.kind.isText else { return }
        mode?.selectedSegment = 1; showEditor()
    }
    @objc private func showFindBar() {
        revealEditor(); findBar.isHidden = false; content.layoutSubtreeIfNeeded(); findBar.focusQuery()
    }
    func performFind(_ action: NSTextFinder.Action) {
        if action == .showFindInterface { showFindBar(); return }
        revealEditor()
        if findBar.isHidden { showFindBar() }
        findBar.navigate(backwards: action == .previousMatch)
    }
    private func showTable() {
        findBar.dismiss()
        do { install(TablePreview(data: try TableData(text: editor.string))) }
        catch { mode?.selectedSegment = 1; showEditor(); let alert = NSAlert(error: error); if let window { alert.beginSheetModal(for: window) } }
    }
    @objc private func switchMode() { mode?.selectedSegment == 0 ? showTable() : showEditor() }
    func textDidChange(_ notification: Notification) { onChange?(titleField.stringValue, editor.string); findBar.editorChanged() }
    func controlTextDidChange(_ notification: Notification) { window?.title = titleField.stringValue; onChange?(titleField.stringValue, editor.string) }
    @objc private func willClose() { onClose?() }
}
