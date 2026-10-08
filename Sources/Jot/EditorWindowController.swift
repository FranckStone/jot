import AppKit
import UniformTypeIdentifiers
import JotCore

final class EditorWindowController: NSWindowController, NSTextViewDelegate, NSTextFieldDelegate, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSMenuDelegate {
    private let store = DraftStore(directory: DraftStore.defaultDirectory())
    private var workspace: Workspace
    private var saveTask: DispatchWorkItem?
    private var noticeTask: DispatchWorkItem?
    private var dirty = false
    private var loading = false
    private var filteredIDs: [UUID] = []
    private var recentlyDeleted: Draft?
    private var deletedIndex = 0
    private let titleField = NSTextField()
    private let searchField = NSSearchField()
    private let table = NSTableView()
    private let draftCount = label("1", size: 11, color: Palette.muted)
    private let saveLabel = label("已保存到本机", size: 11, color: Palette.muted)
    private let saveIcon = NSImageView()
    private let statisticsLabel = label("0 字符  ·  1 行", size: 11, color: Palette.muted)
    private let cursorLabel = label("行 1，列 1  ·  UTF-8", size: 11, color: Palette.muted)
    private let fontLabel = label("16", size: 12, color: Palette.muted)
    private let noticeLabel = label("", size: 12, color: Palette.muted)
    private let editorScroll = NSScrollView()
    private let textView = NSTextView()
    private var emptyState: EmptyStateView!
    private var wrapButton: NSButton!
    private var codeButton: NSButton!
    private var undoDeleteButton: NSButton!
    private var copyButton: NSButton!
    private var initialWarning: String?

    init() {
        let result = store.load()
        workspace = result.workspace
        initialWarning = result.warning
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Jot"
        window.titlebarAppearsTransparent = true
        configureWindowChrome(window, identifier: "Jot.EditorChrome")
        window.backgroundColor = Palette.backdrop
        window.minSize = NSSize(width: 850, height: 600)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.setFrameAutosaveName("Jot.MainWindow")
        super.init(window: window)
        window.delegate = self
        buildInterface()
        reloadDrafts()
        loadSelectedDraft()
        if !result.canSave { setSaveStatus("自动保存已暂停", failed: true) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeFirstResponder(textView)
        if let warning = initialWarning {
            initialWarning = nil
            DispatchQueue.main.async { [weak self] in self?.showError("草稿恢复提示", detail: warning) }
        }
    }

    private func buildInterface() {
        let root = SurfaceView(Palette.backdrop)
        window?.contentView = root
        let sidebar = buildSidebar()
        let main = buildWorkspace()
        [main, sidebar].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 252),
            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), main.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            main.topAnchor.constraint(equalTo: root.topAnchor), main.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        let logo = LogoView()
        let wordmark = label("Jot.", size: 30, weight: .semibold)
        let subtitle = label("给文字一个落脚处", size: 11, color: Palette.muted)
        let brandWords = NSStackView(views: [wordmark, subtitle])
        brandWords.orientation = .vertical
        brandWords.alignment = .leading
        brandWords.spacing = 3
        let brand = NSStackView(views: [logo, brandWords])
        brand.spacing = 12
        let new = button("新建草稿", symbol: "plus", target: self, action: #selector(newDraft(_:)), primary: true)
        new.toolTip = "新建草稿（⌘N）"
        let newCapsule = controlCapsule(new, primary: true)
        searchField.placeholderString = "搜索草稿"
        searchField.placeholderAttributedString = NSAttributedString(string: "搜索草稿", attributes: [.foregroundColor: Palette.muted, .font: NSFont.systemFont(ofSize: 12)])
        searchField.font = .systemFont(ofSize: 12)
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.setAccessibilityLabel("搜索草稿")
        let listHeading = NSStackView(views: [label("我的草稿", size: 11, weight: .medium, color: Palette.muted), NSView(), draftCount])
        listHeading.orientation = .horizontal
        table.addTableColumn(NSTableColumn(identifier: .init("draft")))
        table.headerView = nil
        table.rowHeight = 72
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel("我的草稿列表")
        let context = NSMenu()
        context.delegate = self
        let delete = NSMenuItem(title: "删除草稿…", action: #selector(deleteDraft(_:)), keyEquivalent: "")
        delete.target = self
        context.addItem(delete)
        table.menu = context
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        let importButton = button("导入文本文件", symbol: "square.and.arrow.down", target: self, action: #selector(importFile(_:)))
        importButton.isBordered = false
        let privacy = label("保存在本机，内容不上传", size: 11, color: Palette.muted)
        let privacyImage = NSImageView(image: symbol("lock.shield", size: 12) ?? NSImage())
        privacyImage.contentTintColor = Palette.muted
        let privacyRow = NSStackView(views: [privacyImage, privacy])
        privacyRow.spacing = 7
        let bottomRule = RuleView()
        let foot = label("简单一点，专心写。", size: 11, color: Palette.muted)
        let deleteButton = button("", symbol: "trash", target: self, action: #selector(deleteDraft(_:)))
        deleteButton.isBordered = false
        deleteButton.toolTip = "删除当前草稿"
        deleteButton.setAccessibilityLabel("删除当前草稿")
        let footer = NSStackView(views: [foot, NSView(), deleteButton])
        footer.orientation = .horizontal
        let items: [NSView] = [brand, newCapsule, searchField, listHeading, scroll, importButton, privacyRow, bottomRule, footer]
        items.forEach { $0.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview($0) }
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 44), logo.heightAnchor.constraint(equalToConstant: 44),
            brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 26), brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 28),
            newCapsule.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 28), newCapsule.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20), newCapsule.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -20),
            searchField.topAnchor.constraint(equalTo: newCapsule.bottomAnchor, constant: 20), searchField.leadingAnchor.constraint(equalTo: newCapsule.leadingAnchor), searchField.trailingAnchor.constraint(equalTo: newCapsule.trailingAnchor), searchField.heightAnchor.constraint(equalToConstant: 30),
            listHeading.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 28), listHeading.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -28), listHeading.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 23),
            scroll.topAnchor.constraint(equalTo: listHeading.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 13), scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -13), scroll.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -12),
            importButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20), importButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -20), importButton.bottomAnchor.constraint(equalTo: privacyRow.topAnchor, constant: -10),
            privacyRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 28), privacyRow.bottomAnchor.constraint(equalTo: bottomRule.topAnchor, constant: -22),
            bottomRule.heightAnchor.constraint(equalToConstant: 1), bottomRule.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20), bottomRule.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -20), bottomRule.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 28), footer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -20), footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -10), footer.heightAnchor.constraint(equalToConstant: 34)
        ])
        return sidebar
    }

    private func buildWorkspace() -> NSView {
        let main = SurfaceView(Palette.backdrop)
        let header = NSView()
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.font = .systemFont(ofSize: 24, weight: .semibold)
        titleField.textColor = Palette.ink
        titleField.placeholderString = "未命名草稿"
        titleField.placeholderAttributedString = NSAttributedString(string: "未命名草稿", attributes: [.foregroundColor: Palette.muted, .font: NSFont.systemFont(ofSize: 24, weight: .semibold)])
        titleField.delegate = self
        titleField.setAccessibilityLabel("草稿名称")
        saveIcon.image = symbol("checkmark.circle", size: 12)
        saveIcon.contentTintColor = Palette.accent
        let saved = NSStackView(views: [saveIcon, saveLabel])
        saved.spacing = 5
        let identity = NSView()
        [titleField, saved].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; identity.addSubview($0) }
        titleField.setContentCompressionResistancePriority(.required, for: .horizontal)
        let export = button("导出", symbol: "square.and.arrow.up", target: self, action: #selector(exportFile(_:)))
        export.isBordered = false
        copyButton = button("复制全文", symbol: "doc.on.doc", target: self, action: #selector(copyAll(_:)), primary: true)
        let copyCapsule = controlCapsule(copyButton, primary: true)
        let actions = NSStackView(views: [export, copyCapsule])
        actions.spacing = 12
        [identity, actions].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; header.addSubview($0) }
        NSLayoutConstraint.activate([
            identity.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 32), identity.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            identity.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -24),
            identity.heightAnchor.constraint(equalToConstant: 54),
            titleField.leadingAnchor.constraint(equalTo: identity.leadingAnchor), titleField.trailingAnchor.constraint(equalTo: identity.trailingAnchor),
            titleField.topAnchor.constraint(equalTo: identity.topAnchor), titleField.heightAnchor.constraint(equalToConstant: 30),
            saved.leadingAnchor.constraint(equalTo: identity.leadingAnchor), saved.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 8), saved.heightAnchor.constraint(equalToConstant: 16),
            export.widthAnchor.constraint(equalToConstant: 72), copyCapsule.widthAnchor.constraint(equalToConstant: 124),
            actions.widthAnchor.constraint(equalToConstant: 208),
            actions.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -28), actions.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        let toolbar = buildToolbar()
        configureTextView()
        let editorArea = SurfaceView(Palette.paper, cornerRadius: 20)
        editorScroll.translatesAutoresizingMaskIntoConstraints = false
        editorArea.addSubview(editorScroll)
        emptyState = EmptyStateView(target: self, action: #selector(pasteClipboard(_:)))
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        editorArea.addSubview(emptyState)
        let preferredEmptyTop = emptyState.topAnchor.constraint(equalTo: editorArea.topAnchor, constant: 95)
        preferredEmptyTop.priority = .defaultHigh
        NSLayoutConstraint.activate([
            editorScroll.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor), editorScroll.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor),
            editorScroll.topAnchor.constraint(equalTo: editorArea.topAnchor), editorScroll.bottomAnchor.constraint(equalTo: editorArea.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: editorArea.leadingAnchor, constant: 38), emptyState.trailingAnchor.constraint(equalTo: editorArea.trailingAnchor, constant: -26),
            preferredEmptyTop,
            emptyState.topAnchor.constraint(greaterThanOrEqualTo: editorArea.topAnchor, constant: 22),
            emptyState.bottomAnchor.constraint(lessThanOrEqualTo: editorArea.bottomAnchor, constant: -10),
            emptyState.heightAnchor.constraint(equalToConstant: 285)
        ])
        let footer = NSStackView(views: [statisticsLabel, NSView(), cursorLabel])
        footer.orientation = .horizontal
        footer.edgeInsets = NSEdgeInsets(top: 0, left: 28, bottom: 0, right: 28)
        let notice = NSStackView()
        notice.orientation = .horizontal
        notice.spacing = 10
        notice.edgeInsets = NSEdgeInsets(top: 0, left: 30, bottom: 0, right: 28)
        undoDeleteButton = button("撤销删除", target: self, action: #selector(undoDelete(_:)))
        undoDeleteButton.isBordered = false
        undoDeleteButton.isHidden = true
        notice.addArrangedSubview(noticeLabel)
        notice.addArrangedSubview(undoDeleteButton)
        notice.addArrangedSubview(NSView())
        let parts: [NSView] = [header, toolbar, editorArea, notice, footer]
        parts.forEach { $0.translatesAutoresizingMaskIntoConstraints = false; main.addSubview($0) }
        for part in [header, notice, footer] {
            part.leadingAnchor.constraint(equalTo: main.leadingAnchor).isActive = true
            part.trailingAnchor.constraint(equalTo: main.trailingAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: main.topAnchor), header.heightAnchor.constraint(equalToConstant: 103),
            toolbar.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 20), toolbar.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -20),
            toolbar.topAnchor.constraint(equalTo: header.bottomAnchor), toolbar.heightAnchor.constraint(equalToConstant: 48),
            editorArea.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 20), editorArea.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -20),
            editorArea.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 16), editorArea.bottomAnchor.constraint(equalTo: notice.topAnchor),
            notice.bottomAnchor.constraint(equalTo: footer.topAnchor), notice.heightAnchor.constraint(equalToConstant: 34),
            footer.bottomAnchor.constraint(equalTo: main.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 39)
        ])
        return main
    }

    private func buildToolbar() -> NSView {
        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 7
        toolbar.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        codeButton = button("纯文本", symbol: "textformat", target: self, action: #selector(toggleCodeMode(_:)))
        codeButton.isBordered = false
        codeButton.toolTip = "切换纯文本与等宽代码字体"
        let smaller = button("", symbol: "minus", target: self, action: #selector(decreaseFont(_:)))
        smaller.isBordered = false
        smaller.toolTip = "缩小字号"
        smaller.setAccessibilityLabel("缩小字号")
        let larger = button("", symbol: "plus", target: self, action: #selector(increaseFont(_:)))
        larger.isBordered = false
        larger.toolTip = "放大字号"
        larger.setAccessibilityLabel("放大字号")
        wrapButton = button("自动换行", symbol: "arrow.turn.down.left", target: self, action: #selector(toggleWrap(_:)))
        wrapButton.isBordered = false
        let find = button("查找替换", symbol: "magnifyingglass", target: self, action: #selector(showFind(_:)))
        find.isBordered = false
        let tools = button("整理文本", symbol: "slider.horizontal.3", target: self, action: #selector(showTools(_:)))
        tools.isBordered = false
        [codeButton!, smaller, fontLabel, larger, NSView(), wrapButton!, find, tools].forEach { toolbar.addArrangedSubview($0) }
        smaller.widthAnchor.constraint(equalToConstant: 28).isActive = true
        larger.widthAnchor.constraint(equalToConstant: 28).isActive = true
        return glassPanel(content: toolbar)
    }

    private func configureTextView() {
        editorScroll.hasVerticalScroller = true
        editorScroll.autohidesScrollers = true
        editorScroll.drawsBackground = false
        editorScroll.borderType = .noBorder
        editorScroll.findBarPosition = .aboveContent
        textView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 32, height: 22)
        textView.textColor = Palette.ink
        textView.insertionPointColor = Palette.accent
        textView.backgroundColor = Palette.paper
        textView.selectedTextAttributes = [.backgroundColor: Palette.selected, .foregroundColor: Palette.ink]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.delegate = self
        textView.setAccessibilityLabel("文本编辑区")
        editorScroll.documentView = textView
        applyEditorSettings()
    }

    private func applyEditorSettings() {
        let font = workspace.codeMode ? NSFont.monospacedSystemFont(ofSize: workspace.fontSize, weight: .regular) : NSFont.systemFont(ofSize: workspace.fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = workspace.fontSize * 0.45
        textView.font = font
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: font, .foregroundColor: Palette.ink, .paragraphStyle: paragraph]
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes([.font: font, .foregroundColor: Palette.ink, .paragraphStyle: paragraph], range: NSRange(location: 0, length: storage.length))
        }
        textView.isHorizontallyResizable = !workspace.wrapsLines
        textView.autoresizingMask = workspace.wrapsLines ? [.width] : []
        textView.textContainer?.widthTracksTextView = workspace.wrapsLines
        textView.textContainer?.containerSize = NSSize(width: workspace.wrapsLines ? editorScroll.contentSize.width : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if workspace.wrapsLines { textView.setFrameSize(NSSize(width: editorScroll.contentSize.width, height: textView.frame.height)) }
        editorScroll.hasHorizontalScroller = !workspace.wrapsLines
        fontLabel.stringValue = String(Int(workspace.fontSize))
        codeButton?.title = workspace.codeMode ? "代码 / 数据" : "纯文本"
        wrapButton?.contentTintColor = workspace.wrapsLines ? Palette.accent : Palette.muted
        wrapButton?.toolTip = workspace.wrapsLines ? "自动换行已开启" : "自动换行已关闭"
        wrapButton?.setAccessibilityValue(workspace.wrapsLines ? "开启" : "关闭")
    }

    private func loadSelectedDraft() {
        loading = true
        let draft = workspace.drafts[workspace.selectedIndex]
        titleField.stringValue = draft.title
        textView.breakUndoCoalescing()
        textView.string = draft.text
        textView.undoManager?.removeAllActions()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        applyEditorSettings()
        loading = false
        refreshEditorState()
        window?.title = "\(draft.displayTitle) — Jot"
    }

    private func syncCurrentDraft() {
        let index = workspace.selectedIndex
        guard workspace.drafts[index].text != textView.string || workspace.drafts[index].title != titleField.stringValue else { return }
        workspace.drafts[index].text = textView.string
        workspace.drafts[index].title = String(titleField.stringValue.prefix(120))
        workspace.drafts[index].modifiedAt = Date()
        dirty = true
    }

    private func reloadDrafts() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredIDs = workspace.drafts.filter { query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) }.map(\.id)
        loading = true
        table.reloadData()
        if let row = filteredIDs.firstIndex(of: workspace.selectedID) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else { table.deselectAll(nil) }
        loading = false
        draftCount.stringValue = query.isEmpty ? "\(workspace.drafts.count)" : "\(filteredIDs.count) / \(workspace.drafts.count)"
    }

    private func refreshEditorState() {
        emptyState?.isHidden = !textView.string.isEmpty
        copyButton?.isEnabled = !textView.string.isEmpty
        let stats = TextStatistics(text: textView.string, utf16Cursor: textView.selectedRange().location)
        let selection = textView.selectedRange()
        var counts = "\(stats.characters.formatted()) 字符  ·  \(stats.lines.formatted()) 行"
        if selection.length > 0, NSMaxRange(selection) <= (textView.string as NSString).length {
            counts += "  ·  已选 \((textView.string as NSString).substring(with: selection).count) 字符"
        }
        statisticsLabel.stringValue = counts
        cursorLabel.stringValue = "行 \(stats.cursorLine)，列 \(stats.cursorColumn)  ·  UTF-8"
    }

    private func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        setSaveStatus("正在保存…")
        let task = DispatchWorkItem { [weak self] in _ = self?.flushSave() }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    @discardableResult func flushSave() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        syncCurrentDraft()
        guard dirty else { return true }
        do {
            try store.save(workspace)
            dirty = false
            setSaveStatus("已保存到本机")
            saveIcon.image = symbol("checkmark.circle.fill", size: 12)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard self?.dirty == false else { return }
                self?.saveIcon.image = symbol("checkmark.circle", size: 12)
            }
            return true
        } catch {
            setSaveStatus("保存失败，请导出内容", failed: true)
            noticeLabel.stringValue = error.localizedDescription
            return false
        }
    }

    private func setSaveStatus(_ text: String, failed: Bool = false) {
        saveLabel.stringValue = text
        saveLabel.textColor = failed ? .systemRed : Palette.muted
        saveIcon.contentTintColor = failed ? .systemRed : Palette.accent
        saveIcon.image = symbol(failed ? "exclamationmark.circle" : "checkmark.circle", size: 12)
        saveLabel.setAccessibilityValue(text)
    }

    private func notice(_ text: String, undo: Bool = false) {
        noticeTask?.cancel()
        noticeLabel.stringValue = text
        undoDeleteButton.isHidden = recentlyDeleted == nil
        // A deletion remains recoverable until another deletion or the app exits.
        guard !undo else { return }
        let task = DispatchWorkItem { [weak self] in self?.noticeLabel.stringValue = "" }
        noticeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: task)
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        if let window = window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filteredIDs.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { DraftRowView() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredIDs.count, let draft = workspace.drafts.first(where: { $0.id == filteredIDs[row] }) else { return nil }
        let cell = DraftCell(frame: .zero)
        cell.nameLabel.stringValue = draft.displayTitle
        cell.previewLabel.stringValue = draft.preview
        cell.setAccessibilityLabel("\(draft.displayTitle)，\(draft.preview)")
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !loading, table.selectedRow >= 0, table.selectedRow < filteredIDs.count else { return }
        let selected = filteredIDs[table.selectedRow]
        guard selected != workspace.selectedID else { return }
        syncCurrentDraft()
        workspace.selectedID = selected
        loadSelectedDraft()
        scheduleSave()
        window?.makeFirstResponder(textView)
    }

    func menuWillOpen(_ menu: NSMenu) {
        let row = table.clickedRow
        if row >= 0 && row < filteredIDs.count { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
    }

    func textDidChange(_ notification: Notification) {
        guard !loading else { return }
        syncCurrentDraft()
        refreshEditorState()
        reloadDrafts()
        scheduleSave()
    }

    func textViewDidChangeSelection(_ notification: Notification) { if !loading { refreshEditorState() } }

    func controlTextDidChange(_ notification: Notification) {
        guard !loading, let field = notification.object as? NSTextField else { return }
        if field === searchField { reloadDrafts(); return }
        if field === titleField {
            if titleField.stringValue.count > 120 { titleField.stringValue = String(titleField.stringValue.prefix(120)) }
            syncCurrentDraft()
            reloadDrafts()
            window?.title = "\(workspace.drafts[workspace.selectedIndex].displayTitle) — Jot"
            scheduleSave()
        }
    }

    @objc func newDraft(_ sender: Any?) {
        syncCurrentDraft()
        let draft = Draft()
        workspace.drafts.insert(draft, at: 0)
        workspace.selectedID = draft.id
        searchField.stringValue = ""
        reloadDrafts()
        loadSelectedDraft()
        scheduleSave()
        window?.makeFirstResponder(textView)
    }

    @objc func copyAll(_ sender: Any?) {
        guard !textView.string.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(textView.string, forType: .string) { notice("已复制全文") }
        else { notice("复制失败，请选择文本后按 ⌘C 重试") }
    }

    @objc func pasteClipboard(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { notice("剪贴板没有文本内容，可使用 ⌘V 粘贴"); return }
        window?.makeFirstResponder(textView)
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    @objc func showFind(_ sender: Any?) { performFind(.showFindInterface) }
    @objc func findNext(_ sender: Any?) { performFind(.nextMatch) }
    @objc func findPrevious(_ sender: Any?) { performFind(.previousMatch) }
    private func performFind(_ action: NSTextFinder.Action) {
        window?.makeFirstResponder(textView)
        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }

    @objc func showTools(_ sender: Any?) {
        guard let view = sender as? NSView else { return }
        let menu = NSMenu()
        for (title, action) in [("格式化 JSON", #selector(formatJSON(_:))), ("去除行首尾空格", #selector(trimLines(_:))), ("移除空白行", #selector(removeBlankLines(_:))), ("去除重复行", #selector(uniqueLines(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 2), in: view)
    }

    @objc func formatJSON(_ sender: Any?) { transform(.formatJSON, name: "格式化 JSON") }
    @objc func trimLines(_ sender: Any?) { transform(.trimLines, name: "去除行首尾空格") }
    @objc func removeBlankLines(_ sender: Any?) { transform(.removeBlankLines, name: "移除空白行") }
    @objc func uniqueLines(_ sender: Any?) { transform(.uniqueLines, name: "去除重复行") }

    private func transform(_ transform: TextTransform, name: String) {
        let fullText = textView.string as NSString
        guard fullText.length > 0 else { notice("先粘贴或输入一些内容"); return }
        let selection = textView.selectedRange()
        let range = selection.length > 0 ? selection : NSRange(location: 0, length: fullText.length)
        do {
            let original = fullText.substring(with: range)
            let result = try transform.apply(to: original)
            guard original != result else { notice("内容已经整理好了"); return }
            window?.makeFirstResponder(textView)
            textView.breakUndoCoalescing()
            textView.insertText(result, replacementRange: range)
            textView.breakUndoCoalescing()
            textView.undoManager?.setActionName(name)
            notice("\(name)完成，可按 ⌘Z 撤销")
        } catch {
            showError("JSON 格式不正确", detail: "\(error.localizedDescription)\n原文已保留，请检查后再试。")
        }
    }

    @objc func toggleWrap(_ sender: Any?) { workspace.wrapsLines.toggle(); applyEditorSettings(); scheduleSave() }
    @objc func toggleCodeMode(_ sender: Any?) { workspace.codeMode.toggle(); applyEditorSettings(); scheduleSave() }
    @objc func increaseFont(_ sender: Any?) { workspace.fontSize = min(28, workspace.fontSize + 1); applyEditorSettings(); scheduleSave() }
    @objc func decreaseFont(_ sender: Any?) { workspace.fontSize = max(12, workspace.fontSize - 1); applyEditorSettings(); scheduleSave() }

    @objc func importFile(_ sender: Any?) {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.title = "导入文本文件"
        panel.message = "文件会复制为一份新草稿，原文件保持不变。"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.text, .json]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls { self?.importURL(url) }
        }
    }

    func importURL(_ url: URL) {
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 10 * 1024 * 1024 else { showError("文件太大", detail: "当前版本支持导入 10 MB 以内的文本文件。"); return }
            var encoding = String.Encoding.utf8
            let text = try String(contentsOf: url, usedEncoding: &encoding)
            syncCurrentDraft()
            let draft = Draft(title: url.deletingPathExtension().lastPathComponent, text: text)
            workspace.drafts.insert(draft, at: 0)
            workspace.selectedID = draft.id
            searchField.stringValue = ""
            reloadDrafts()
            loadSelectedDraft()
            scheduleSave()
            notice("已导入 \(url.lastPathComponent)")
        } catch { showError("无法导入文件", detail: "请选择可读取的文本文件。\n\(error.localizedDescription)") }
    }

    @objc func exportFile(_ sender: Any?) {
        guard let window = window else { return }
        syncCurrentDraft()
        let draft = workspace.drafts[workspace.selectedIndex]
        let panel = NSSavePanel()
        panel.title = "导出草稿"
        panel.nameFieldStringValue = draft.exportName
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try draft.text.write(to: url, atomically: true, encoding: .utf8); self?.notice("已导出 \(url.lastPathComponent)") }
            catch { self?.showError("导出失败", detail: error.localizedDescription) }
        }
    }

    @objc func deleteDraft(_ sender: Any?) {
        guard let window = window else { return }
        syncCurrentDraft()
        let draft = workspace.drafts[workspace.selectedIndex]
        let alert = NSAlert()
        alert.messageText = "删除“\(draft.displayTitle)”？"
        alert.informativeText = "删除后，可在窗口底部撤销这次删除。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "删除草稿")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertSecondButtonReturn, let self = self else { return }
            self.deletedIndex = self.workspace.selectedIndex
            self.recentlyDeleted = self.workspace.drafts.remove(at: self.deletedIndex)
            if self.workspace.drafts.isEmpty { self.workspace.drafts.append(Draft()) }
            self.workspace.selectedID = self.workspace.drafts[min(self.deletedIndex, self.workspace.drafts.count - 1)].id
            self.reloadDrafts()
            self.loadSelectedDraft()
            self.scheduleSave()
            self.notice("草稿已删除", undo: true)
        }
    }

    @objc func undoDelete(_ sender: Any?) {
        guard let draft = recentlyDeleted else { return }
        syncCurrentDraft()
        workspace.drafts.insert(draft, at: min(deletedIndex, workspace.drafts.count))
        workspace.selectedID = draft.id
        recentlyDeleted = nil
        searchField.stringValue = ""
        reloadDrafts()
        loadSelectedDraft()
        scheduleSave()
        notice("已恢复草稿")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if flushSave() { return true }
        let alert = NSAlert()
        alert.messageText = "草稿尚未保存"
        alert.informativeText = "请先导出内容，或确认不保存并关闭。"
        alert.addButton(withTitle: "返回编辑")
        alert.addButton(withTitle: "不保存并关闭")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
