import AppKit
import JotCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: WorkbenchWindowController?
    // Cold launches deliver files before the workbench exists.
    private var pendingFiles: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Read the bundled file directly so Dock does not keep an older Launch Services icon.
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let url = Bundle.main.url(forResource: name, withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        controller = WorkbenchWindowController()
        installMenu()
        controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        pendingFiles.forEach { controller?.importURL($0) }
        pendingFiles.removeAll()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = controller, !controller.flushSave() else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "工作台尚未保存"
        alert.informativeText = "请返回 Jot 导出内容，或在确认后不保存并退出。"
        alert.addButton(withTitle: "返回编辑")
        alert.addButton(withTitle: "不保存并退出")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let controller { urls.forEach(controller.importURL) } else { pendingFiles += urls }
        sender.reply(toOpenOrPrint: .success)
    }

    private func installMenu() {
        let bar = NSMenu()
        let appMenu = NSMenu(title: "Jot")
        let about = NSMenuItem(title: "关于 Jot", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let services = NSMenu(title: "服务")
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = services
        appMenu.addItem(withTitle: "隐藏 Jot", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Jot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        attach(appMenu, to: bar)

        let file = NSMenu(title: "文件")
        add("新建文本卡片", #selector(WorkbenchWindowController.newDraft(_:)), key: "n", to: file)
        add("添加文件…", #selector(WorkbenchWindowController.importFile(_:)), key: "o", to: file)
        add("导出当前卡片…", #selector(WorkbenchWindowController.exportFile(_:)), key: "s", modifiers: [.command, .shift], to: file)
        file.addItem(.separator())
        add("移除当前卡片", #selector(WorkbenchWindowController.deleteDraft(_:)), to: file)
        file.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        attach(file, to: bar)

        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        add("粘贴为新卡片", #selector(WorkbenchWindowController.pasteClipboard(_:)), key: "v", modifiers: [.command, .shift], to: edit)
        add("复制全文", #selector(WorkbenchWindowController.copyAll(_:)), key: "c", modifiers: [.command, .shift], to: edit)
        add("查找与替换", #selector(WorkbenchWindowController.showFind(_:)), key: "f", to: edit)
        add("查找下一处", #selector(WorkbenchWindowController.findNext(_:)), key: "g", to: edit)
        add("查找上一处", #selector(WorkbenchWindowController.findPrevious(_:)), key: "g", modifiers: [.command, .shift], to: edit)
        attach(edit, to: bar)

        let format = NSMenu(title: "文本")
        add("格式化 JSON", #selector(WorkbenchWindowController.formatJSON(_:)), key: "j", modifiers: [.command, .shift], to: format)
        add("去除行首尾空格", #selector(WorkbenchWindowController.trimLines(_:)), to: format)
        add("移除空白行", #selector(WorkbenchWindowController.removeBlankLines(_:)), to: format)
        add("去除重复行", #selector(WorkbenchWindowController.uniqueLines(_:)), to: format)
        attach(format, to: bar)

        let view = NSMenu(title: "显示")
        add("收起侧栏", #selector(WorkbenchWindowController.toggleSidebar(_:)), key: "s", modifiers: [.control, .command], to: view)
        view.addItem(.separator())
        add("自动换行", #selector(WorkbenchWindowController.toggleWrap(_:)), to: view)
        add("代码字体", #selector(WorkbenchWindowController.toggleCodeMode(_:)), to: view)
        add("放大字号", #selector(WorkbenchWindowController.increaseFont(_:)), key: "+", to: view)
        add("缩小字号", #selector(WorkbenchWindowController.decreaseFont(_:)), key: "-", to: view)
        attach(view, to: bar)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        attach(windowMenu, to: bar)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = bar
    }

    private func attach(_ menu: NSMenu, to bar: NSMenu) {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        bar.addItem(item)
    }

    private func add(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = controller
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
