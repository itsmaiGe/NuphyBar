import AppKit

@MainActor
enum ApplicationMenuFactory {
    static func makeMainMenu(language: AppLanguage = .simplifiedChinese) -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem(title: "NuphyBar", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "NuphyBar")
        let quit = NSMenuItem(
            title: language.text(.quit),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.keyEquivalentModifierMask = .command
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem(title: language.text(.window), action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: language.text(.window))
        let close = NSMenuItem(
            title: language.text(.closeWindow),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        close.keyEquivalentModifierMask = .command
        windowMenu.addItem(close)
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        return mainMenu
    }
}
