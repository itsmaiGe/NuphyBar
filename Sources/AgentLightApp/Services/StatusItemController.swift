import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private static let settingsFrameName = NSWindow.FrameAutosaveName("NuphyBar.SettingsWindow.v9")

    private let model: AppModel
    private let statusItem: NSStatusItem
    private let contextMenu = NSMenu()
    private var settingsWindowController: NSWindowController?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusButton()
        configureContextMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: .nuphyBarLanguageDidChange,
            object: nil
        )
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = menuBarIcon
        button.imagePosition = .imageOnly
        button.toolTip = "NuphyBar"
    }

    private func configureContextMenu() {
        let language = AppLanguage.current
        contextMenu.removeAllItems()
        let settings = NSMenuItem(
            title: language.text(.settings),
            action: #selector(handleSettingsMenuItem(_:)),
            keyEquivalent: ""
        )
        settings.target = self
        settings.image = nil
        contextMenu.addItem(settings)

        let quit = NSMenuItem(
            title: language.text(.quit),
            action: #selector(quitApplication),
            keyEquivalent: ""
        )
        quit.target = self
        contextMenu.addItem(quit)
        statusItem.menu = contextMenu
    }

    @objc private func languageDidChange(_ notification: Notification) {
        configureContextMenu()
    }

    @objc private func handleSettingsMenuItem(_ sender: NSMenuItem) {
        DispatchQueue.main.async { [weak self] in
            self?.presentPreferencesWindow()
        }
    }

    private func presentPreferencesWindow() {
        model.refreshConnection()
        model.refreshIntegrations()

        if settingsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: SettingsLayout.windowWidth,
                    height: SettingsLayout.windowHeight
                ),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "NuphyBar"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = true
            window.isOpaque = true
            window.backgroundColor = NuphyBarTheme.windowBackgroundColor
            window.isMovableByWindowBackground = false
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SettingsView(model: model)
            )
            window.setContentSize(
                NSSize(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
            )
            let windowController = NSWindowController(window: window)
            windowController.shouldCascadeWindows = false
            let restoredFrame = window.setFrameUsingName(Self.settingsFrameName, force: true)
            _ = window.setFrameAutosaveName(Self.settingsFrameName)
            if !restoredFrame {
                center(window)
            }
            settingsWindowController = windowController
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window = settingsWindowController?.window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderFrontRegardless()
            window.makeKey()
        }
    }

    private func center(_ window: NSWindow) {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let windowFrame = window.frame
        window.setFrame(
            NSRect(
                origin: NSPoint(
                    x: visibleFrame.midX - windowFrame.width / 2,
                    y: visibleFrame.midY - windowFrame.height / 2
                ),
                size: windowFrame.size
            ),
            display: true,
            animate: false
        )
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private var menuBarIcon: NSImage {
        guard let url = Bundle.main.url(
            forResource: "NuphyBarMenuBarIcon",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "keyboard", accessibilityDescription: "NuphyBar")!
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
