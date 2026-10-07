import AppKit
import AgentLightHID

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
        let statusItemController = StatusItemController(model: model)
        self.statusItemController = statusItemController

        if NuPhyHIDTransport.accessState != .granted {
            statusItemController.presentPreferencesWindow()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        statusItemController?.presentPreferencesWindow()
        return true
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
