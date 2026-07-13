import AppKit
import Testing
@testable import AgentLightApp

@MainActor
@Test("application menu exposes standard close and quit shortcuts")
func applicationMenuHasStandardShortcuts() throws {
    let menu = ApplicationMenuFactory.makeMainMenu()

    let appMenu = try #require(menu.item(withTitle: "NuphyBar")?.submenu)
    let quit = try #require(appMenu.item(withTitle: "退出"))
    #expect(quit.keyEquivalent == "q")
    #expect(quit.keyEquivalentModifierMask == .command)

    let windowMenu = try #require(menu.item(withTitle: "窗口")?.submenu)
    let close = try #require(windowMenu.item(withTitle: "关闭窗口"))
    #expect(close.keyEquivalent == "w")
    #expect(close.keyEquivalentModifierMask == .command)
    #expect(close.action == #selector(NSWindow.performClose(_:)))
}

@MainActor
@Test("application menu follows the selected English language")
func applicationMenuSupportsEnglish() throws {
    let menu = ApplicationMenuFactory.makeMainMenu(language: .english)

    let appMenu = try #require(menu.item(withTitle: "NuphyBar")?.submenu)
    #expect(appMenu.item(withTitle: "Quit") != nil)

    let windowMenu = try #require(menu.item(withTitle: "Window")?.submenu)
    #expect(windowMenu.item(withTitle: "Close Window") != nil)
}
