import Foundation
import SwiftUI

enum AppText {
    case settings
    case quit
    case window
    case closeWindow
    case agentTab
    case keyboardTab
    case aboutTab
    case agentIntegrations
    case codexApprovalRequired
    case unavailable
    case connect
    case pending
    case remove
    case connected
    case connectionStatus
    case lightStatus
    case bluetoothConnected
    case checkAgain
    case allowAccess
    case nuphyKeyboard
    case checkingKeyboard
    case accessRequired
    case keyboardNotFound
    case working
    case blueFlow
    case waiting
    case amberFlash
    case taskComplete
    case greenBreath
    case idle
    case factoryEffect
    case language
    case launchAtLogin
    case launchAtLoginApproval
    case launchAtLoginFailed
    case aboutDescription
    case followOnX
}

enum AppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "appLanguage"

    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    static var current: AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: storageKey),
              let language = AppLanguage(rawValue: rawValue) else {
            return .simplifiedChinese
        }
        return language
    }

    func text(_ key: AppText) -> String {
        switch (self, key) {
        case (.simplifiedChinese, .settings): "设置"
        case (.english, .settings): "Settings"
        case (.simplifiedChinese, .quit): "退出"
        case (.english, .quit): "Quit"
        case (.simplifiedChinese, .window): "窗口"
        case (.english, .window): "Window"
        case (.simplifiedChinese, .closeWindow): "关闭窗口"
        case (.english, .closeWindow): "Close Window"
        case (.simplifiedChinese, .agentTab): "Agent"
        case (.english, .agentTab): "Agent"
        case (.simplifiedChinese, .keyboardTab): "键盘"
        case (.english, .keyboardTab): "Keyboard"
        case (.simplifiedChinese, .aboutTab): "关于"
        case (.english, .aboutTab): "About"
        case (.simplifiedChinese, .agentIntegrations): "Agent 接入"
        case (.english, .agentIntegrations): "Agent Integrations"
        case (.simplifiedChinese, .codexApprovalRequired):
            "Codex Hooks 尚未获准运行。请在 Codex 的 /hooks 中确认，然后重新打开任务。"
        case (.english, .codexApprovalRequired):
            "Codex hooks need approval. Confirm them in Codex /hooks, then reopen the task."
        case (.simplifiedChinese, .unavailable): "未检测到"
        case (.english, .unavailable): "Not Found"
        case (.simplifiedChinese, .connect): "接入"
        case (.english, .connect): "Connect"
        case (.simplifiedChinese, .pending): "待确认"
        case (.english, .pending): "Pending"
        case (.simplifiedChinese, .remove): "移除"
        case (.english, .remove): "Remove"
        case (.simplifiedChinese, .connected): "已接入"
        case (.english, .connected): "Connected"
        case (.simplifiedChinese, .connectionStatus): "连接状态"
        case (.english, .connectionStatus): "Connection"
        case (.simplifiedChinese, .lightStatus): "灯光状态"
        case (.english, .lightStatus): "Light Status"
        case (.simplifiedChinese, .bluetoothConnected): "蓝牙已连接"
        case (.english, .bluetoothConnected): "Bluetooth Connected"
        case (.simplifiedChinese, .checkAgain): "重新检测"
        case (.english, .checkAgain): "Check Again"
        case (.simplifiedChinese, .allowAccess): "允许访问"
        case (.english, .allowAccess): "Allow Access"
        case (.simplifiedChinese, .nuphyKeyboard): "NuPhy 键盘"
        case (.english, .nuphyKeyboard): "NuPhy Keyboard"
        case (.simplifiedChinese, .checkingKeyboard): "正在检查键盘…"
        case (.english, .checkingKeyboard): "Checking keyboard…"
        case (.simplifiedChinese, .accessRequired): "需要键盘访问权限"
        case (.english, .accessRequired): "Keyboard access required"
        case (.simplifiedChinese, .keyboardNotFound): "未找到兼容的 NuPhy 键盘"
        case (.english, .keyboardNotFound): "No compatible NuPhy keyboard found"
        case (.simplifiedChinese, .working): "工作中"
        case (.english, .working): "Working"
        case (.simplifiedChinese, .blueFlow): "蓝色流光"
        case (.english, .blueFlow): "Blue Flow"
        case (.simplifiedChinese, .waiting): "等待操作"
        case (.english, .waiting): "Waiting"
        case (.simplifiedChinese, .amberFlash): "琥珀闪烁"
        case (.english, .amberFlash): "Amber Flash"
        case (.simplifiedChinese, .taskComplete): "任务完成"
        case (.english, .taskComplete): "Complete"
        case (.simplifiedChinese, .greenBreath): "绿色呼吸"
        case (.english, .greenBreath): "Green Breath"
        case (.simplifiedChinese, .idle): "待机"
        case (.english, .idle): "Idle"
        case (.simplifiedChinese, .factoryEffect): "恢复原厂灯效"
        case (.english, .factoryEffect): "Factory Effect"
        case (.simplifiedChinese, .language): "语言"
        case (.english, .language): "Language"
        case (.simplifiedChinese, .launchAtLogin): "开机时自动启动"
        case (.english, .launchAtLogin): "Launch at Login"
        case (.simplifiedChinese, .launchAtLoginApproval): "需要在系统设置的登录项中允许 NuphyBar"
        case (.english, .launchAtLoginApproval): "Allow NuphyBar in System Settings > Login Items"
        case (.simplifiedChinese, .launchAtLoginFailed): "无法更改开机自启："
        case (.english, .launchAtLoginFailed): "Could not change launch at login:"
        case (.simplifiedChinese, .aboutDescription): "让 NuPhy 侧灯显示本机 Agent 状态"
        case (.english, .aboutDescription): "Show local Agent status on your NuPhy side lights"
        case (.simplifiedChinese, .followOnX): "作者麦格 · 在 X 上关注我"
        case (.english, .followOnX): "Maige · Follow me on X"
        }
    }

    func integrationSaved(providerName: String) -> String {
        switch self {
        case .simplifiedChinese: "更改已保存，请重新打开 \(providerName) 任务。"
        case .english: "Changes saved. Reopen your \(providerName) task."
        }
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppLanguage.simplifiedChinese
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

extension Notification.Name {
    static let nuphyBarLanguageDidChange = Notification.Name("NuphyBarLanguageDidChange")
}
