import AppKit

@MainActor
enum AppMenu {
    static func install(for delegate: AppDelegate) {
        let mainMenu = NSMenu()
        NSApplication.shared.mainMenu = mainMenu

        let appRoot = NSMenuItem()
        mainMenu.addItem(appRoot)
        let appMenu = NSMenu(title: "KaiMD")
        appRoot.submenu = appMenu
        appMenu.addItem(withTitle: "关于 KaiMD", action: #selector(delegate.showAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 KaiMD", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 KaiMD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileRoot = NSMenuItem()
        mainMenu.addItem(fileRoot)
        let fileMenu = NSMenu(title: "文件")
        fileRoot.submenu = fileMenu
        let newFile = fileMenu.addItem(withTitle: "新建 Markdown 文件", action: #selector(delegate.newMarkdownFile(_:)), keyEquivalent: "n")
        newFile.target = delegate
        let open = fileMenu.addItem(withTitle: "打开…", action: #selector(delegate.openItem(_:)), keyEquivalent: "o")
        open.target = delegate
        let quickOpen = fileMenu.addItem(withTitle: "快速打开文件", action: #selector(delegate.quickOpen(_:)), keyEquivalent: "o")
        quickOpen.keyEquivalentModifierMask = [.command, .shift]
        quickOpen.target = delegate
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "保存", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(withTitle: "另存为…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "在 Finder 中显示", action: #selector(delegate.revealCurrentDocument(_:)), keyEquivalent: "")

        let editRoot = NSMenuItem()
        mainMenu.addItem(editRoot)
        let editMenu = NSMenu(title: "编辑")
        editRoot.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let find = editMenu.addItem(withTitle: "查找…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = NSTextFinder.Action.showFindInterface.rawValue
        let replace = editMenu.addItem(withTitle: "查找并替换…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        replace.keyEquivalentModifierMask = [.command, .option]
        replace.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        let workspaceSearch = editMenu.addItem(withTitle: "在工作区中搜索", action: #selector(delegate.workspaceSearch(_:)), keyEquivalent: "f")
        workspaceSearch.keyEquivalentModifierMask = [.command, .shift]
        workspaceSearch.target = delegate

        let formatRoot = NSMenuItem()
        mainMenu.addItem(formatRoot)
        let formatMenu = NSMenu(title: "格式")
        formatRoot.submenu = formatMenu
        let bold = formatMenu.addItem(withTitle: "粗体", action: #selector(delegate.insertBold(_:)), keyEquivalent: "b")
        bold.target = delegate
        let italic = formatMenu.addItem(withTitle: "斜体", action: #selector(delegate.insertItalic(_:)), keyEquivalent: "i")
        italic.target = delegate
        let link = formatMenu.addItem(withTitle: "链接", action: #selector(delegate.insertLink(_:)), keyEquivalent: "k")
        link.target = delegate

        let viewRoot = NSMenuItem()
        mainMenu.addItem(viewRoot)
        let viewMenu = NSMenu(title: "显示")
        viewRoot.submenu = viewMenu
        addViewItem("源码模式", key: "1", action: #selector(delegate.sourceMode(_:)), to: viewMenu, target: delegate)
        addViewItem("分栏模式", key: "2", action: #selector(delegate.splitMode(_:)), to: viewMenu, target: delegate)
        addViewItem("预览模式", key: "3", action: #selector(delegate.previewMode(_:)), to: viewMenu, target: delegate)
        viewMenu.addItem(.separator())
        let sidebar = viewMenu.addItem(withTitle: "显示或隐藏侧栏", action: #selector(delegate.toggleSidebar(_:)), keyEquivalent: "\\")
        sidebar.target = delegate

        let windowRoot = NSMenuItem()
        mainMenu.addItem(windowRoot)
        let windowMenu = NSMenu(title: "窗口")
        windowRoot.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApplication.shared.windowsMenu = windowMenu

        let helpRoot = NSMenuItem()
        mainMenu.addItem(helpRoot)
        let helpMenu = NSMenu(title: "帮助")
        helpRoot.submenu = helpMenu
        let welcome = helpMenu.addItem(withTitle: "KaiMD 使用提示", action: #selector(delegate.showWelcome(_:)), keyEquivalent: "")
        welcome.target = delegate
        NSApplication.shared.helpMenu = helpMenu
    }

    private static func addViewItem(
        _ title: String,
        key: String,
        action: Selector,
        to menu: NSMenu,
        target: AnyObject
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = target
    }
}
