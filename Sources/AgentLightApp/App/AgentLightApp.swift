import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        refreshApplicationMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: .nuphyBarLanguageDidChange,
            object: nil
        )
        statusItemController = StatusItemController(model: model)
    }

    @objc private func languageDidChange(_ notification: Notification) {
        refreshApplicationMenu()
    }

    private func refreshApplicationMenu() {
        let language = AppLanguage.current
        let mainMenu = ApplicationMenuFactory.makeMainMenu(language: language)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = mainMenu.item(withTitle: language.text(.window))?.submenu
    }
}

@main
@MainActor
enum NuphyBarApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.delegate = appDelegate
        application.run()
    }
}
