import AppKit
import QuartzCore
import PDFKit
import Vision
import UniformTypeIdentifiers
import JotCore

final class WorkbenchWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuItemValidation {
    private let store = WorkbenchStore(directory: DraftStore.defaultDirectory())
    private var board: Workbench
    private var cards: [UUID: BoardCardView] = [:]
    private var details: [UUID: ItemDetailController] = [:]
    private var visibleIDs: [UUID] = []
    private var filter: ItemKind?
    private var dirty = false
    private var saveTask: DispatchWorkItem?
    // Encoding and writing large workbenches stays off the main thread; the store is confined to this queue.
    private let saveQueue = DispatchQueue(label: "Jot.WorkbenchSave", qos: .utility)
    private var savesInFlight = 0
    private var saveFailed = false
    private var saveGeneration = 0
    private var processing = Set<UUID>()
    private let history = UndoManager()
    private let canvas = WorkbenchCanvas(frame: NSRect(x: 0, y: 0, width: 2800, height: 1800))
    private let scroll = NSScrollView()
    private let list = NSTableView()
    private let search = NSSearchField()
    private let filterControl = FeedbackPopUpButton(frame: .zero, pullsDown: false)
    private let status = label("已保存到本机", size: 11, color: Palette.muted)
    private let count = label("", size: 11, color: Palette.muted)
    private let zoomLabel = label("100%", size: 11, color: Palette.muted)
    private let selectedLabel = label("选择卡片，查看可用工具", size: 12, color: Palette.muted)
    private var toolsButton: NSButton!
    private var focusButton: NSButton!
    private var rebuildingList = false
    private var loadingWarning: String?
    private var eventMonitor: Any?
    private var editorSettings = EditorSettings.load()
    private let sidebar = NSVisualEffectView()
    private var sidebarLeading: NSLayoutConstraint!
    private var sidebarToggle: NSButton!
    private var sidebarCollapsed = UserDefaults.standard.bool(forKey: "Jot.SidebarCollapsed")
    private var sidebarTransition = 0

    init() {
        let loaded = store.load(); board = loaded.workbench; loadingWarning = loaded.warning
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1360, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Jot — 我的工作台"; window.titlebarAppearsTransparent = true
        configureWindowChrome(window, identifier: "Jot.WorkbenchChrome")
        window.backgroundColor = Palette.backdrop; window.minSize = NSSize(width: 1080, height: 680)
        window.isReleasedWhenClosed = false; window.tabbingMode = .disallowed
        window.center(); window.setFrameAutosaveName("Jot.WorkbenchWindow")
        super.init(window: window); window.delegate = self
        buildInterface(); rebuildCards(); updateList(); updateSelection()
        scroll.magnification = board.zoom; updateZoomLabel()
        if !loaded.canSave { status.stringValue = "自动保存已暂停"; status.textColor = .systemRed }
        else { scheduleSave() }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let point = self.canvas.convert(event.locationInWindow, from: nil)
            if self.scroll.contentView.bounds.contains(point), let card = self.canvas.subviews.reversed().compactMap({ $0 as? BoardCardView }).first(where: { !$0.isHidden && $0.frame.contains(point) }) {
                self.select(card.itemID, reveal: false)
            }
            return event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(zoomChanged), name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; NotificationCenter.default.removeObserver(self) }
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender); window?.makeFirstResponder(canvas)
        if let warning = loadingWarning { loadingWarning = nil; DispatchQueue.main.async { [weak self] in self?.showError(warning) } }
    }
    private var selectedItem: BoardItem? {
        if let id = details.first(where: { $0.value.window === NSApp.keyWindow })?.key { return board.items.first { $0.id == id } }
        return board.items.first { $0.id == board.selectedID }
    }

    private func buildInterface() {
        let root = SurfaceView(Palette.backdrop); root.wantsLayer = true; root.layer?.masksToBounds = true; window?.contentView = root
        sidebar.material = .sidebar; sidebar.blendingMode = .withinWindow; sidebar.state = .active
        let main = NSView()
        [sidebar, main].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        sidebarLeading = sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: sidebarCollapsed ? -220 : 0)
        sidebar.isHidden = sidebarCollapsed
        NSLayoutConstraint.activate([
            sidebarLeading, sidebar.topAnchor.constraint(equalTo: root.topAnchor), sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 220),
            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), main.trailingAnchor.constraint(equalTo: root.trailingAnchor), main.topAnchor.constraint(equalTo: root.topAnchor), main.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        let logo = LogoView(); logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 36).isActive = true; logo.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let words = NSStackView(views: [label("Jot.", size: 26, weight: .semibold), label("你的本地数据工作台", size: 10, color: Palette.muted)])
        words.orientation = .vertical; words.alignment = .leading; words.spacing = 2
        let brand = NSStackView(views: [logo, words]); brand.spacing = 10
        let all = button("我的工作台", symbol: "square.grid.2x2", target: self, action: #selector(showAll)); all.isBordered = false; all.alignment = .left
        filterControl.addItems(withTitles: ["全部类型"] + ItemKind.allCases.map(\.label))
        filterControl.item(at: 0)?.image = symbol("line.3.horizontal.decrease", size: 13)
        for (index, kind) in ItemKind.allCases.enumerated() { filterControl.item(at: index + 1)?.image = symbol(kind.symbolName, size: 13) }
        filterControl.toolTip = "按数据类型筛选工作台"
        filterControl.target = self; filterControl.action = #selector(filterChanged(_:)); filterControl.setAccessibilityLabel("筛选数据类型")
        search.placeholderString = "搜索名称与文本"; search.delegate = self; search.sendsSearchStringImmediately = true; search.setAccessibilityLabel("搜索工作台")
        list.addTableColumn(NSTableColumn(identifier: .init("item"))); list.headerView = nil
        list.rowHeight = 49; list.intercellSpacing = .zero; list.dataSource = self; list.delegate = self
        list.allowsEmptySelection = true; list.backgroundColor = .clear; list.setAccessibilityLabel("工作台数据列表")
        list.target = self; list.doubleAction = #selector(focusSelected)
        let listScroll = NSScrollView(); listScroll.documentView = list; listScroll.hasVerticalScroller = true; listScroll.autohidesScrollers = true; listScroll.drawsBackground = false
        let privacy = label("保存在本机\n文件与处理结果自动保存", size: 10, color: Palette.muted)
        let sidebarItems: [NSView] = [brand, all, filterControl, search, count, listScroll, privacy]
        sidebarItems.forEach { $0.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview($0) }
        NSLayoutConstraint.activate([
            brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 26), brand.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 20),
            all.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 28), all.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16), all.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            search.topAnchor.constraint(equalTo: all.bottomAnchor, constant: 18), search.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16), search.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16), search.heightAnchor.constraint(equalToConstant: 28),
            filterControl.heightAnchor.constraint(equalToConstant: 34), filterControl.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12), filterControl.leadingAnchor.constraint(equalTo: search.leadingAnchor), filterControl.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            count.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 24), count.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22),
            listScroll.topAnchor.constraint(equalTo: count.bottomAnchor, constant: 10), listScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8), listScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -8), listScroll.bottomAnchor.constraint(equalTo: privacy.topAnchor, constant: -20),
            privacy.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 22), privacy.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -20)
        ])
        sidebarToggle = button("", symbol: "sidebar.left", target: self, action: #selector(toggleSidebar(_:)))
        sidebarToggle.widthAnchor.constraint(equalToConstant: 34).isActive = true
        updateSidebarToggle()
        let title = label("我的工作台", size: 24, weight: .semibold)
        let subtitle = label("放下文件，连接想法，处理数据。", size: 12, color: Palette.muted)
        let titles = NSStackView(views: [title, subtitle]); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 7
        let new = button("新建文本", symbol: "plus", target: self, action: #selector(newDraft(_:)))
        let paste = button("粘贴", symbol: "doc.on.clipboard", target: self, action: #selector(pasteClipboard(_:)))
        paste.toolTip = "将剪贴板内容添加为新卡片（⇧⌘V）"
        let importButton = button("添加文件", symbol: "square.and.arrow.down", target: self, action: #selector(importFile(_:)), primary: true)
        let actions = NSStackView(views: [new, paste, controlCapsule(importButton, primary: true)]); actions.spacing = 12
        toolsButton = button("卡片工具", symbol: "slider.horizontal.3", target: self, action: #selector(showTools(_:)))
        focusButton = button("专注查看", symbol: "arrow.up.left.and.arrow.down.right", target: self, action: #selector(focusSelected))
        let toolRow = NSStackView(views: [selectedLabel, NSView(), focusButton, toolsButton]); toolRow.spacing = 12
        toolRow.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 12)
        let toolbar = glassPanel(content: toolRow, cornerRadius: 18)
        scroll.documentView = canvas; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.allowsMagnification = true; scroll.minMagnification = Workbench.minimumZoom; scroll.maxMagnification = Workbench.maximumZoom
        canvas.onDrop = { [weak self] pasteboard, point in self?.ingest(pasteboard, at: point) ?? false }
        canvas.onPaste = { [weak self] in self?.pasteClipboard(nil) }
        canvas.onClearSelection = { [weak self] in self?.board.selectedID = nil; self?.updateSelection() }
        let minus = button("", symbol: "minus", target: self, action: #selector(zoomOut)); minus.setAccessibilityLabel("缩小画布"); minus.toolTip = "缩小画布"
        let plus = button("", symbol: "plus", target: self, action: #selector(zoomIn)); plus.setAccessibilityLabel("放大画布"); plus.toolTip = "放大画布"
        let reset = button("100%", target: self, action: #selector(resetZoom))
        let arrange = button("整理排列", symbol: "rectangle.grid.2x2", target: self, action: #selector(arrangeCards))
        let footer = NSStackView(views: [status, NSView(), arrange, minus, zoomLabel, plus, reset]); footer.spacing = 10; footer.alignment = .centerY
        [sidebarToggle!, titles, actions, toolbar, scroll, footer].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; main.addSubview($0) }
        NSLayoutConstraint.activate([
            sidebarToggle.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 28), sidebarToggle.centerYAnchor.constraint(equalTo: titles.centerYAnchor),
            titles.leadingAnchor.constraint(equalTo: sidebarToggle.trailingAnchor, constant: 12), titles.topAnchor.constraint(equalTo: main.topAnchor, constant: 25),
            actions.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -28), actions.centerYAnchor.constraint(equalTo: titles.centerYAnchor), actions.leadingAnchor.constraint(greaterThanOrEqualTo: titles.trailingAnchor, constant: 24),
            toolbar.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 22), toolbar.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -22), toolbar.topAnchor.constraint(equalTo: main.topAnchor, constant: 102), toolbar.heightAnchor.constraint(equalToConstant: 44),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: main.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: main.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -4),
            footer.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 24), footer.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -20), footer.bottomAnchor.constraint(equalTo: main.bottomAnchor, constant: -8), footer.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @objc func toggleSidebar(_ sender: Any?) {
        guard let root = window?.contentView else { return }
        sidebarCollapsed.toggle()
        UserDefaults.standard.set(sidebarCollapsed, forKey: "Jot.SidebarCollapsed")
        sidebarTransition += 1
        let transition = sidebarTransition
        if sidebarCollapsed, let responder = window?.firstResponder as? NSView,
           responder.isDescendant(of: sidebar) || responder === search.currentEditor() {
            window?.makeFirstResponder(sidebarToggle)
        }
        updateSidebarToggle()
        root.layoutSubtreeIfNeeded()
        sidebar.isHidden = false
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.22 : 0
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            context.allowsImplicitAnimation = animate
            sidebarLeading.constant = sidebarCollapsed ? -220 : 0
            root.layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            guard let self, self.sidebarTransition == transition else { return }
            self.sidebar.isHidden = self.sidebarCollapsed
        }
    }
    private func updateSidebarToggle() {
        let action = sidebarCollapsed ? "展开侧栏" : "收起侧栏"
        sidebarToggle.toolTip = "\(action)（⌃⌘S）"
        sidebarToggle.setAccessibilityLabel(action)
        sidebarToggle.setAccessibilityValue(sidebarCollapsed ? "已收起" : "已展开")
    }

    private func rebuildCards() {
        cards.values.forEach { $0.removeFromSuperview() }; cards.removeAll()
        for item in board.items { installCard(item) }
        resizeCanvas(); canvas.hasItems = !board.items.isEmpty; applyVisibility(); updateSelection()
    }
    private func installCard(_ item: BoardItem) {
        let card = BoardCardView(item: item, url: store.attachmentURL(for: item))
        card.onSelect = { [weak self] id in self?.select(id, reveal: false) }
        card.onOpen = { [weak self] id in self?.openDetail(id) }
        card.onDuplicate = { [weak self] id in self?.duplicateItem(id: id) }
        card.onDelete = { [weak self] id in self?.removeCard(id: id) }
        card.onFrameChange = { [weak self] id, frame in
            guard let self, let index = self.board.items.firstIndex(where: { $0.id == id }) else { return }
            let old = self.board
            self.board.items[index].x = frame.minX; self.board.items[index].y = frame.minY
            self.board.items[index].width = frame.width; self.board.items[index].height = frame.height
            if old != self.board { self.recordUndo(old, name: "调整卡片"); self.resizeCanvas(); self.scheduleSave() }
        }
        cards[item.id] = card; canvas.addSubview(card)
    }
    private func refreshCard(_ id: UUID) {
        guard let item = board.items.first(where: { $0.id == id }) else { return }
        cards[id]?.removeFromSuperview(); installCard(item); applyVisibility(); updateSelection()
    }
    private func resizeCanvas() {
        let width = max(1800, board.items.map { $0.x + $0.width + 240 }.max() ?? 0)
        let height = max(1200, board.items.map { $0.y + $0.height + 240 }.max() ?? 0)
        canvas.setFrameSize(NSSize(width: width, height: height))
    }
    private func select(_ id: UUID, reveal: Bool) {
        board.selectedID = id; updateSelection()
        if reveal, let card = cards[id] { canvas.scrollToVisible(card.frame.insetBy(dx: -24, dy: -24)) }
    }
    private func updateSelection() {
        for (id, card) in cards { card.selected = id == board.selectedID; card.isProcessing = processing.contains(id) }
        if let id = board.selectedID, let card = cards[id] { canvas.addSubview(card, positioned: .above, relativeTo: nil) }
        let item = board.items.first { $0.id == board.selectedID }
        selectedLabel.stringValue = item.map { "\($0.kind.label)  ·  \($0.displayTitle)" } ?? "选择卡片，查看可用工具"
        selectedLabel.lineBreakMode = .byTruncatingTail
        toolsButton.isEnabled = item != nil && !processing.contains(item!.id); focusButton.isEnabled = item != nil
        rebuildingList = true
        if let row = visibleIDs.firstIndex(where: { $0 == board.selectedID }) { list.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else { list.deselectAll(nil) }
        rebuildingList = false
    }
    private func updateList() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleIDs = board.items.reversed().filter { (filter == nil || $0.kind == filter) && (query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) || ($0.kind.isText && $0.text.localizedCaseInsensitiveContains(query))) }.map(\.id)
        count.stringValue = "\(visibleIDs.count) 项内容" + (visibleIDs.count == board.items.count ? "" : " / 共 \(board.items.count) 项")
        rebuildingList = true; list.reloadData(); rebuildingList = false
        applyVisibility(); updateSelection()
    }
    private func applyVisibility() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        for item in board.items {
            cards[item.id]?.isHidden = !(filter == nil || item.kind == filter) || (!query.isEmpty && !item.displayTitle.localizedCaseInsensitiveContains(query) && !item.text.localizedCaseInsensitiveContains(query))
        }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIDs.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = board.items.first(where: { $0.id == visibleIDs[row] }) else { return nil }
        let icon = NSImageView(image: symbol(item.kind.symbolName, size: 14) ?? NSImage()); icon.contentTintColor = Palette.muted
        let titles = NSStackView(views: [label(item.displayTitle, size: 12, weight: .medium), label(item.operation ?? item.kind.label, size: 10, color: Palette.muted)])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        let rowView = NSStackView(views: [icon, titles]); rowView.spacing = 10; rowView.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        return rowView
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !rebuildingList, visibleIDs.indices.contains(list.selectedRow) else { return }
        select(visibleIDs[list.selectedRow], reveal: true)
    }
    func controlTextDidChange(_ notification: Notification) { updateList() }
    @objc private func filterChanged(_ sender: NSPopUpButton) { filter = sender.indexOfSelectedItem == 0 ? nil : ItemKind.allCases[sender.indexOfSelectedItem - 1]; updateList() }
    @objc private func showAll() { filter = nil; filterControl.selectItem(at: 0); search.stringValue = ""; updateList() }

    private func insertionPoint() -> NSPoint {
        let visible = scroll.documentVisibleRect
        let offset = CGFloat(board.items.count % 5) * 28
        return NSPoint(x: visible.minX + 40 + offset, y: visible.minY + 40 + offset)
    }
    private func add(_ item: BoardItem, undo: Bool = true) {
        if undo { recordUndo(board, name: "添加卡片") }
        board.items.append(item); board.selectedID = item.id
        filter = nil; filterControl.selectItem(at: 0); search.stringValue = ""
        installCard(item); resizeCanvas(); canvas.hasItems = true; updateList(); list.scrollRowToVisible(0); select(item.id, reveal: true); scheduleSave()
    }
    private func result(_ text: String, from source: BoardItem, operation: String, kind: ItemKind? = nil) {
        var target = NSRect(x: source.x + source.width + 32, y: source.y, width: source.width, height: source.height)
        while board.items.contains(where: { NSRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height).insetBy(dx: -16, dy: -16).intersects(target) }) {
            target.origin.y += source.height + 32
        }
        let item = BoardItem(title: "\(source.displayTitle) · \(operation)", kind: kind ?? ItemKind.detect(text: text), text: text,
                             x: target.minX, y: target.minY, width: source.width, height: source.height, sourceID: source.id, operation: operation)
        add(item)
    }
    @objc func newDraft(_ sender: Any?) {
        let point = insertionPoint()
        let item = BoardItem(x: point.x, y: point.y)
        add(item); openDetail(item.id)
    }
    @objc func pasteClipboard(_ sender: Any?) { if !ingest(.general, at: insertionPoint()) { showError("剪贴板里没有可用的文本、图片或文件。") } }
    @discardableResult private func ingest(_ pasteboard: NSPasteboard, at point: NSPoint) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for (index, url) in urls.enumerated() { importURL(url, at: NSPoint(x: point.x + CGFloat(index % 3) * 400, y: point.y + CGFloat(index / 3) * 360)) }; return true
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            guard text.utf8.count <= 10 * 1024 * 1024 else { showError("文本超过 10 MB，请拆分后粘贴。"); return true }
            let title = String(text.split(whereSeparator: \.isNewline).first?.prefix(32) ?? "粘贴的文本")
            add(BoardItem(title: title, kind: ItemKind.detect(text: text), text: text, x: point.x, y: point.y)); return true
        }
        if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
            do { let name = try store.saveImageData(data); add(BoardItem(title: "粘贴的图片", kind: .image, attachment: name, originalName: "图片.png", x: point.x, y: point.y, height: 360)) }
            catch { showError(error.localizedDescription) }
            return true
        }
        return false
    }
    @objc func importFile(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "添加 PDF、图片、表格或其他文件，Jot 会保存一份本机副本。"; panel.prompt = "添加到工作台"
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            let point = self.insertionPoint()
            for (index, url) in panel.urls.enumerated() { self.importURL(url, at: NSPoint(x: point.x + CGFloat(index % 3) * 400, y: point.y + CGFloat(index / 3) * 360)) }
        }
    }
    func importURL(_ url: URL) { importURL(url, at: insertionPoint()) }
    private func importURL(_ url: URL, at point: NSPoint) {
        let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
            guard info.isRegularFile == true else { throw failure("只支持文件，请展开文件夹后添加。") }
            guard (info.fileSize ?? 0) <= 100 * 1024 * 1024 else { throw failure("\(url.lastPathComponent) 超过 100 MB，请拆分后添加。") }
            let ext = url.pathExtension.lowercased()
            let textExtensions: Set<String> = ["txt", "text", "md", "json", "csv", "tsv", "log", "xml", "yaml", "yml", "js", "ts", "swift", "py", "sql", "sh", "html", "css", "ini", "cfg"]
            let kind: ItemKind
            var text = ""
            if textExtensions.contains(ext) || info.contentType?.conforms(to: .plainText) == true {
                guard (info.fileSize ?? 0) <= 10 * 1024 * 1024 else { throw failure("文本文件最多 10 MB，请拆分后添加。") }
                let data = try Data(contentsOf: url)
                guard let decoded = String(data: data, encoding: .utf8) ?? ((data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])) ? String(data: data, encoding: .utf16) : nil) else { throw failure("无法读取文本编码，请转换为 UTF-8 或 UTF-16。") }
                text = decoded.hasPrefix("\u{feff}") ? String(decoded.dropFirst()) : decoded
                kind = (ext == "csv" || ext == "tsv") ? .table : (ext == "json" ? .json : ItemKind.detect(text: text))
            } else if ext == "pdf" { kind = .pdf }
            else if info.contentType?.conforms(to: .image) == true { kind = .image }
            else { kind = .file }
            let attachment = try store.copyAttachment(from: url)
            add(BoardItem(title: url.lastPathComponent, kind: kind, text: text, attachment: attachment, originalName: url.lastPathComponent, x: point.x, y: point.y, height: kind == .image || kind == .pdf ? 400 : 320))
        } catch { showError("\(url.lastPathComponent)：\(error.localizedDescription)") }
    }

    @objc private func focusSelected() { if let item = selectedItem { openDetail(item.id) } }
    private func openDetail(_ id: UUID) {
        guard let item = board.items.first(where: { $0.id == id }) else { return }
        if let controller = details[id] { controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil); return }
        let controller = ItemDetailController(item: item, url: store.attachmentURL(for: item), settings: editorSettings)
        controller.onChange = { [weak self] title, text in
            guard let self, let index = self.board.items.firstIndex(where: { $0.id == id }) else { return }
            self.board.items[index].title = title
            if self.board.items[index].kind.isText { self.board.items[index].text = text }
            self.board.items[index].modifiedAt = Date(); self.scheduleSave()
            self.cards[id]?.titleLabel.stringValue = self.board.items[index].displayTitle
        }
        controller.onClose = { [weak self] in
            guard let self else { return }; self.details.removeValue(forKey: id)
            self.refreshCard(id); self.updateList(); self.saveInBackground()
        }
        details[id] = controller; controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showTools(_ sender: Any?) {
        guard let item = selectedItem else { return }
        let menu = NSMenu()
        func entry(_ title: String, _ action: Selector) { let entry = NSMenuItem(title: title, action: action, keyEquivalent: ""); entry.target = self; menu.addItem(entry) }
        if item.kind == .pdf { entry("提取 PDF 文字 → 新卡片", #selector(extractPDF)) }
        if item.kind == .image { entry("识别图片文字 → 新卡片", #selector(recognizeImage)) }
        if item.kind.isText {
            entry("格式化 JSON → 新卡片", #selector(formatJSON(_:)))
            entry("去除行首尾空格 → 新卡片", #selector(trimLines(_:)))
            entry("移除空白行 → 新卡片", #selector(removeBlankLines(_:)))
            entry("去除重复行 → 新卡片", #selector(uniqueLines(_:)))
            if item.kind == .table { entry("表格转 JSON → 新卡片", #selector(tableToJSON)) }
            if item.kind == .json { entry("JSON 数组转表格 → 新卡片", #selector(jsonToTable)) }
            entry("复制全文", #selector(copyAll(_:)))
        }
        menu.addItem(.separator())
        entry("复制卡片", #selector(duplicateCard))
        entry("导出…", #selector(exportFile(_:)))
        if item.attachment != nil { entry("打开导入时的原件副本", #selector(openOriginal)) }
        if item.sourceID != nil { entry("定位来源卡片", #selector(revealSource)) }
        menu.addItem(.separator()); entry("从工作台移除（可撤销）", #selector(deleteDraft(_:)))
        if let sender = sender as? NSView { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender) }
    }
    @objc func formatJSON(_ sender: Any?) { transform(.formatJSON, title: "JSON 格式化") }
    @objc func trimLines(_ sender: Any?) { transform(.trimLines, title: "清理空格") }
    @objc func removeBlankLines(_ sender: Any?) { transform(.removeBlankLines, title: "移除空白行") }
    @objc func uniqueLines(_ sender: Any?) { transform(.uniqueLines, title: "行去重") }
    private func transform(_ transform: TextTransform, title: String) {
        guard let item = selectedItem, item.kind.isText else { return }
        do { result(try transform.apply(to: item.text), from: item, operation: title) }
        catch { showError(error.localizedDescription) }
    }
    @objc private func tableToJSON() {
        guard let item = selectedItem, item.kind == .table else { return }
        do { result(try TableData(text: item.text).json(), from: item, operation: "表格转 JSON", kind: .json) }
        catch { showError(error.localizedDescription) }
    }
    @objc private func jsonToTable() {
        guard let item = selectedItem, item.kind == .json else { return }
        do {
            guard let objects = try JSONSerialization.jsonObject(with: Data(item.text.utf8)) as? [[String: Any]], !objects.isEmpty else { throw failure("请使用非空的 JSON 对象数组，例如 [{\"名称\":\"Jot\"}]。") }
            let keys = Array(Set(objects.flatMap { $0.keys })).sorted()
            guard keys.count <= 200, objects.count <= 20_000 else { throw TableDataError.tooLarge }
            func cell(_ value: Any?) throws -> String {
                guard let value, !(value is NSNull) else { return "" }
                if let string = value as? String { return string }
                return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
            }
            var table = try TableData(text: "")
            table.rows = [keys] + (try objects.map { object in try keys.map { try cell(object[$0]) } })
            result(table.csv, from: item, operation: "JSON 转表格", kind: .table)
        } catch { showError(error.localizedDescription) }
    }
    @objc private func extractPDF() {
        guard let item = selectedItem, let url = store.attachmentURL(for: item) else { return }
        runProcessing(item, operation: "PDF 提取文字") {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked else { throw self.failure("PDF 无法读取或已加密，请先解锁后导入。") }
            var pages: [String] = []
            for index in 0..<pdf.pageCount {
                if let text = pdf.page(at: index)?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pages.append("—— 第 \(index + 1) 页 ——\n\(text)") }
            }
            guard !pages.isEmpty else { throw self.failure("PDF 没有可提取的文字层。扫描件可先将页面导出为图片，再使用图片文字识别。") }
            return pages.joined(separator: "\n\n")
        }
    }
    @objc private func recognizeImage() {
        guard let item = selectedItem, let url = store.attachmentURL(for: item) else { return }
        runProcessing(item, operation: "图片文字识别") {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            try VNImageRequestHandler(url: url, options: [:]).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.isEmpty else { throw self.failure("没有识别到文字，请尝试更清晰的图片。") }
            return text
        }
    }
    private func runProcessing(_ item: BoardItem, operation: String, work: @escaping () throws -> String) {
        guard !processing.contains(item.id) else { return }
        processing.insert(item.id); status.stringValue = "正在\(operation)…"; updateSelection()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = Result { try work() }
            DispatchQueue.main.async {
                guard let self else { return }; self.processing.remove(item.id); self.updateSelection()
                switch output {
                case .success(let text): self.result(text, from: item, operation: operation)
                case .failure(let error): self.status.stringValue = "处理未完成"; self.showError(error.localizedDescription)
                }
            }
        }
    }
    @objc private func duplicateCard() {
        guard let id = selectedItem?.id else { return }
        duplicateItem(id: id)
    }
    private func duplicateItem(id: UUID) {
        guard let source = board.items.first(where: { $0.id == id }) else { return }
        var copy = source; copy.id = UUID(); copy.title += " · 副本"; copy.x += 40; copy.y += 40; copy.modifiedAt = Date()
        add(copy)
    }
    @objc private func revealSource() {
        guard let sourceID = selectedItem?.sourceID, board.items.contains(where: { $0.id == sourceID }) else { showError("来源卡片已从工作台移除。"); return }
        filter = nil; filterControl.selectItem(at: 0); search.stringValue = ""; updateList(); select(sourceID, reveal: true); window?.makeKeyAndOrderFront(nil)
    }
    @objc private func openOriginal() {
        guard let item = selectedItem, let url = store.attachmentURL(for: item) else { return }
        if !NSWorkspace.shared.open(url) { showError("无法打开原件副本，请检查文件是否仍存在。") }
    }
    @objc func copyAll(_ sender: Any?) {
        guard let item = selectedItem, item.kind.isText else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text, forType: .string)
    }
    @objc func exportFile(_ sender: Any?) {
        guard let item = selectedItem, let window = NSApp.keyWindow ?? window else { return }
        let panel = NSSavePanel()
        let safeName = item.displayTitle.components(separatedBy: CharacterSet(charactersIn: "/\\:\n\r\0")).joined(separator: "-")
        let tableExtension = ((item.originalName ?? item.displayTitle) as NSString).pathExtension.lowercased() == "tsv" ? "tsv" : "csv"
        let ext = item.kind == .json ? "json" : (item.kind == .table ? tableExtension : "txt")
        panel.nameFieldStringValue = item.kind.isText ? ((safeName as NSString).deletingPathExtension + "." + ext) : (item.originalName ?? safeName)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                if item.kind.isText {
                    // Export remains a lossless escape hatch even while structured input is invalid.
                    try item.text.write(to: url, atomically: true, encoding: .utf8)
                } else if let source = self.store.attachmentURL(for: item) { try Data(contentsOf: source).write(to: url, options: .atomic) }
            } catch { self.showError(error.localizedDescription) }
        }
    }
    @objc func deleteDraft(_ sender: Any?) {
        guard let id = selectedItem?.id else { return }
        removeCard(id: id)
    }
    private func removeCard(id: UUID) {
        guard let item = board.items.first(where: { $0.id == id }), !processing.contains(id) else { return }
        details[item.id]?.close(); recordUndo(board, name: "移除卡片")
        board.items.removeAll { $0.id == item.id }; board.selectedID = board.items.last?.id
        rebuildCards(); updateList(); scheduleSave()
    }
    private func recordUndo(_ old: Workbench, name: String) {
        history.registerUndo(withTarget: self) { target in
            let current = target.board
            // Preserve edits to surviving cards made after the structural operation.
            var restored = old
            restored.zoom = current.zoom
            for index in restored.items.indices {
                if let live = current.items.first(where: { $0.id == restored.items[index].id }), live.modifiedAt > restored.items[index].modifiedAt {
                    restored.items[index].text = live.text; restored.items[index].title = live.title; restored.items[index].modifiedAt = live.modifiedAt
                }
            }
            let removed = Set(current.items.map(\.id)).subtracting(restored.items.map(\.id))
            for id in removed { target.details[id]?.close() }
            target.recordUndo(current, name: name); target.board = restored
            target.rebuildCards(); target.updateList(); target.scheduleSave()
        }
        history.setActionName(name)
    }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { history }
    @objc private func arrangeCards() {
        guard !board.items.isEmpty else { return }; recordUndo(board, name: "整理排列")
        var x = 40.0, y = 40.0, rowHeight = 0.0
        for index in board.items.indices.reversed() {
            if x > 40 && x + board.items[index].width > 1280 { x = 40; y += rowHeight + 32; rowHeight = 0 }
            board.items[index].x = x; board.items[index].y = y
            x += board.items[index].width + 32; rowHeight = max(rowHeight, board.items[index].height)
        }
        rebuildCards(); scheduleSave()
    }
    @objc private func zoomIn() { setZoom(scroll.magnification + 0.15) }
    @objc private func zoomOut() { setZoom(scroll.magnification - 0.15) }
    @objc private func resetZoom() { setZoom(1) }
    private func setZoom(_ value: Double) { scroll.setMagnification(min(Workbench.maximumZoom, max(Workbench.minimumZoom, value)), centeredAt: NSPoint(x: scroll.documentVisibleRect.midX, y: scroll.documentVisibleRect.midY)); zoomChanged() }
    @objc private func zoomChanged() { board.zoom = scroll.magnification; updateZoomLabel(); scheduleSave() }
    private func updateZoomLabel() {
        let percent = scroll.magnification * 100
        zoomLabel.stringValue = "\(Int(percent.rounded()))%"
    }
    private func scheduleSave() {
        dirty = true; saveTask?.cancel()
        if processing.isEmpty { status.stringValue = "正在保存…" }
        let task = DispatchWorkItem { [weak self] in self?.saveInBackground() }
        saveTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }
    private func saveInBackground() {
        saveTask?.cancel()
        guard dirty else { return }
        let snapshot = board, store = store
        dirty = false; savesInFlight += 1; saveGeneration += 1
        let generation = saveGeneration
        saveQueue.async { [weak self] in
            let result = Result { try store.save(snapshot) }
            DispatchQueue.main.async { self?.finishSave(result, generation: generation) }
        }
    }
    private func finishSave(_ result: Result<Void, Error>, generation: Int) {
        savesInFlight -= 1
        // A newer save, or a synchronous flush, supersedes this outcome.
        guard generation == saveGeneration else { return }
        switch result {
        case .success: saveFailed = false; showSaved()
        case .failure: saveFailed = true; dirty = true; showSaveFailure()
        }
    }
    /// Blocks until the current board is on disk; used when closing or quitting.
    @discardableResult func flushSave() -> Bool {
        saveTask?.cancel()
        guard dirty || savesInFlight > 0 || saveFailed else { return true }
        let snapshot = board, store = store
        saveGeneration += 1
        let result = saveQueue.sync { Result { try store.save(snapshot) } }
        switch result {
        case .success: dirty = false; saveFailed = false; showSaved(); return true
        case .failure: dirty = true; saveFailed = true; showSaveFailure(); return false
        }
    }
    private func showSaved() { status.textColor = Palette.muted; if processing.isEmpty && !dirty { status.stringValue = "已保存到本机" } }
    private func showSaveFailure() { status.stringValue = "保存失败，请导出内容"; status.textColor = .systemRed }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if flushSave() { return true }
        showError("工作台尚未保存，请先导出需要保留的内容。"); return false
    }
    @objc func showFind(_ sender: Any?) { find(.showFindInterface) }
    @objc func findNext(_ sender: Any?) { find(.nextMatch) }
    @objc func findPrevious(_ sender: Any?) { find(.previousMatch) }
    private func find(_ action: NSTextFinder.Action) {
        guard let item = selectedItem, item.kind.isText else { return }
        openDetail(item.id); details[item.id]?.performFind(action)
    }
    @objc func toggleWrap(_ sender: Any?) { updateEditorSettings { $0.wraps.toggle() } }
    @objc func toggleCodeMode(_ sender: Any?) { updateEditorSettings { $0.codeMode.toggle() } }
    @objc func increaseFont(_ sender: Any?) { updateEditorSettings { $0.fontSize = min(28, $0.fontSize + 1) } }
    @objc func decreaseFont(_ sender: Any?) { updateEditorSettings { $0.fontSize = max(12, $0.fontSize - 1) } }
    private func updateEditorSettings(_ change: (inout EditorSettings) -> Void) {
        change(&editorSettings); editorSettings.save()
        details.values.forEach { $0.apply(editorSettings) }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebar(_:)) {
            menuItem.title = sidebarCollapsed ? "展开侧栏" : "收起侧栏"
            return true
        }
        switch menuItem.action {
        case #selector(toggleWrap(_:)): menuItem.state = editorSettings.wraps ? .on : .off; return true
        case #selector(toggleCodeMode(_:)): menuItem.state = editorSettings.codeMode ? .on : .off; return true
        case #selector(increaseFont(_:)): return editorSettings.fontSize < 28
        case #selector(decreaseFont(_:)): return editorSettings.fontSize > 12
        default: break
        }
        let textActions: [Selector] = [#selector(formatJSON(_:)), #selector(trimLines(_:)), #selector(removeBlankLines(_:)), #selector(uniqueLines(_:)), #selector(copyAll(_:)), #selector(showFind(_:)), #selector(findNext(_:)), #selector(findPrevious(_:))]
        if let action = menuItem.action, textActions.contains(action) { return selectedItem?.kind.isText == true }
        if menuItem.action == #selector(deleteDraft(_:)) || menuItem.action == #selector(exportFile(_:)) { return selectedItem != nil }
        return true
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "Jot.Workbench", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    private func showError(_ text: String) {
        let alert = NSAlert(); alert.messageText = "暂时无法完成"; alert.informativeText = text; alert.addButton(withTitle: "知道了")
        if let window = NSApp.keyWindow ?? window, window.attachedSheet == nil { alert.beginSheetModal(for: window) }
        else { alert.runModal() }
    }
}
