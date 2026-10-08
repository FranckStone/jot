import AppKit
import QuartzCore
import JotCore

/// A localized find/replace surface over the editor's native selection and undo system.
final class FindReplaceBar: NSView, NSTextFieldDelegate {
    private weak var editor: NSTextView?
    var onClose: (() -> Void)?
    private let query = NSTextField()
    private let replacement = NSTextField()
    private let status = label("输入要查找的内容", size: 11, color: Palette.muted)
    private var previousButton: NSButton!
    private var nextButton: NSButton!
    private var replaceButton: NSButton!
    private var replaceAllButton: NSButton!
    private var caseSensitive: NSButton!
    private var wholeWord: NSButton!
    private var matches: [NSRange] = []
    private var pendingSearch: DispatchWorkItem?
    private var selecting = false
    private var search: TextSearch { TextSearch(query: query.stringValue, caseSensitive: caseSensitive.state == .on, wholeWord: wholeWord.state == .on) }

    init(editor: NSTextView) {
        self.editor = editor
        super.init(frame: .zero)
        let surface = SurfaceView(Palette.backdrop, cornerRadius: 14)
        surface.translatesAutoresizingMaskIntoConstraints = false; addSubview(surface)
        let heading = label("查找与替换", size: 12, weight: .semibold)
        let close = button("", symbol: "xmark", target: self, action: #selector(closeBar))
        close.setAccessibilityLabel("关闭查找替换"); close.toolTip = "关闭（Esc）"
        close.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let header = NSStackView(views: [heading, NSView(), status, close]); header.spacing = 10
        previousButton = button("", symbol: "chevron.up", target: self, action: #selector(previousMatch))
        nextButton = button("", symbol: "chevron.down", target: self, action: #selector(nextMatch))
        previousButton.setAccessibilityLabel("上一处匹配"); previousButton.toolTip = "上一处（⇧↩ / ⇧⌘G）"
        nextButton.setAccessibilityLabel("下一处匹配"); nextButton.toolTip = "下一处（↩ / ⌘G）"
        [previousButton!, nextButton!].forEach { $0.widthAnchor.constraint(equalToConstant: 34).isActive = true }
        replaceButton = button("替换", target: self, action: #selector(replaceCurrent))
        replaceAllButton = button("全部替换", target: self, action: #selector(replaceAll), primary: true)
        let findLabel = label("查找", size: 12, color: Palette.muted)
        let replaceLabel = label("替换为", size: 12, color: Palette.muted)
        [findLabel, replaceLabel].forEach { $0.widthAnchor.constraint(equalToConstant: 40).isActive = true }
        let findInput = input(query, placeholder: "输入要查找的文本", name: "查找内容")
        let replaceInput = input(replacement, placeholder: "替换成什么？留空则删除匹配内容", name: "替换内容")
        let findRow = NSStackView(views: [findLabel, findInput, previousButton!, nextButton!]); findRow.spacing = 8
        let replaceRow = NSStackView(views: [replaceLabel, replaceInput, replaceButton!, replaceAllButton!]); replaceRow.spacing = 8
        caseSensitive = NSButton(checkboxWithTitle: "区分大小写", target: self, action: #selector(optionsChanged))
        wholeWord = NSButton(checkboxWithTitle: "完整词语", target: self, action: #selector(optionsChanged))
        [caseSensitive!, wholeWord!].forEach { $0.font = .systemFont(ofSize: 11) }
        let options = NSStackView(views: [caseSensitive!, wholeWord!, NSView(), label("替换后可用 ⌘Z 撤销", size: 10, color: Palette.muted)]); options.spacing = 14
        let rows = NSStackView(views: [header, findRow, replaceRow, options]); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(rows)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor), surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12), rows.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -12), rows.topAnchor.constraint(equalTo: surface.topAnchor, constant: 8), rows.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -12)
        ])
        [header, findRow, replaceRow, options].forEach { $0.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true }
        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification, object: editor)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { pendingSearch?.cancel(); NotificationCenter.default.removeObserver(self) }
    private func input(_ field: NSTextField, placeholder: String, name: String) -> NSView {
        field.placeholderString = placeholder; field.font = .systemFont(ofSize: 13); field.textColor = Palette.ink
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none; field.cell?.focusRingType = .none; field.delegate = self; field.setAccessibilityLabel(name)
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [.foregroundColor: Palette.muted, .font: NSFont.systemFont(ofSize: 13)])
        let shell = TextInputSurface(field: field)
        shell.translatesAutoresizingMaskIntoConstraints = false; field.translatesAutoresizingMaskIntoConstraints = false; shell.addSubview(field)
        NSLayoutConstraint.activate([shell.heightAnchor.constraint(equalToConstant: 34), shell.widthAnchor.constraint(greaterThanOrEqualToConstant: 100), field.leadingAnchor.constraint(equalTo: shell.leadingAnchor, constant: 12), field.trailingAnchor.constraint(equalTo: shell.trailingAnchor, constant: -12), field.centerYAnchor.constraint(equalTo: shell.centerYAnchor)])
        shell.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return shell
    }
    func focusQuery() {
        if let editor, editor.selectedRange().length > 0, editor.selectedRange().length <= 256 {
            let selected = (editor.string as NSString).substring(with: editor.selectedRange())
            if !selected.contains("\n") { query.stringValue = selected }
        }
        refresh(); query.selectText(nil)
    }
    func refresh() {
        pendingSearch?.cancel()
        guard !isHidden, let editor else { return }
        matches = search.ranges(in: editor.string)
        updateHighlights(); updateStatus()
    }
    func editorChanged() { if !isHidden { refresh() } }
    private func clearHighlights() {
        guard let editor else { return }
        editor.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (editor.string as NSString).length))
    }
    private func updateHighlights() {
        clearHighlights()
        guard let editor else { return }
        // Highlight a bounded number of matches while navigation and replacement cover the whole document.
        for range in matches.prefix(1000) { editor.layoutManager?.addTemporaryAttribute(.backgroundColor, value: Palette.adaptive(0xE7E1CE, 0x554B30), forCharacterRange: range) }
        let selected = editor.selectedRange()
        if matches.contains(selected) { editor.layoutManager?.addTemporaryAttribute(.backgroundColor, value: Palette.adaptive(0xC8D8E8, 0x34516A), forCharacterRange: selected) }
    }
    private func updateStatus() {
        let index = editor.flatMap { matches.firstIndex(of: $0.selectedRange()) }
        status.stringValue = query.stringValue.isEmpty ? "输入要查找的内容" : (matches.isEmpty ? "没有找到匹配" : (index.map { "\($0 + 1) / \(matches.count) 处" } ?? "\(matches.count) 处匹配"))
        previousButton.isEnabled = !matches.isEmpty; nextButton.isEnabled = !matches.isEmpty
        replaceButton.isEnabled = index != nil; replaceAllButton.isEnabled = !matches.isEmpty
    }
    @objc private func selectionChanged() { guard !isHidden, !selecting else { return }; refresh() }
    private func select(_ range: NSRange) {
        guard let editor else { return }
        selecting = true; editor.setSelectedRange(range); editor.scrollRangeToVisible(range); selecting = false
        updateHighlights(); updateStatus()
    }
    func navigate(backwards: Bool = false) {
        refresh(); guard let editor, !matches.isEmpty else { return }
        let selected = editor.selectedRange()
        if backwards { select(matches.last(where: { $0.location < selected.location }) ?? matches.last!) }
        else { select(matches.first(where: { $0.location >= NSMaxRange(selected) && $0 != selected }) ?? matches.first!) }
    }
    @objc private func previousMatch() { navigate(backwards: true) }
    @objc private func nextMatch() { navigate() }
    @objc private func optionsChanged() { refresh(); navigate() }
    @objc private func replaceCurrent() {
        refresh(); guard let editor, matches.contains(editor.selectedRange()) else { return }
        guard (editor.string as NSString).substring(with: editor.selectedRange()) != replacement.stringValue else { navigate(); return }
        window?.makeFirstResponder(editor)
        editor.insertText(replacement.stringValue, replacementRange: editor.selectedRange())
        editor.undoManager?.setActionName("替换文本")
        navigate()
    }
    @objc private func replaceAll() {
        refresh(); guard let editor, !matches.isEmpty else { return }
        let count = matches.count
        let result = search.replacingAll(in: editor.string, with: replacement.stringValue)
        let caret = editor.selectedRange().location
        guard result != editor.string else { status.stringValue = "内容相同，无需替换"; return }
        window?.makeFirstResponder(editor)
        if result != editor.string {
            editor.insertText(result, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            editor.undoManager?.setActionName("全部替换")
            editor.setSelectedRange(NSRange(location: min(caret, (result as NSString).length), length: 0))
        }
        refresh(); status.stringValue = "已替换 \(count) 处 · 可撤销"
    }
    @objc private func closeBar() { pendingSearch?.cancel(); clearHighlights(); onClose?(); window?.makeFirstResponder(editor) }
    func dismiss() { closeBar() }
    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === query else { return }
        pendingSearch?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }; self.refresh()
            if let first = self.matches.first { self.select(first) }
        }
        pendingSearch = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { closeBar(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if control === replacement { replaceCurrent() }
            else { navigate(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true) }
            return true
        }
        return false
    }
}
