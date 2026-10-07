import AgentLightHID
import SwiftUI

struct KeyboardSettingsView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel

    var body: some View {
        SettingsPage {
            SettingsGroup(title: language.text(.connectionStatus)) {
                HStack(spacing: 9) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(NuphyBarTheme.secondaryText)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(keyboardName)
                            .font(.system(size: SettingsLayout.primaryTextSize, weight: .medium))
                        HStack(spacing: 5) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(statusText)
                                .font(.system(size: SettingsLayout.secondaryTextSize))
                                .foregroundStyle(NuphyBarTheme.secondaryText)
                        }
                    }

                    Spacer()

                    if model.hidAccessState == .granted {
                        Button(language.text(.checkAgain)) { model.refreshConnection() }
                            .font(.system(size: SettingsLayout.actionTextSize))
                            .controlSize(.small)
                    } else {
                        Button(language.text(.allowAccess)) { model.requestHIDAccess() }
                            .font(.system(size: SettingsLayout.actionTextSize))
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(height: 44)

                Divider()

                HStack {
                    Text(language.text(.recoveryDiagnostics))
                        .font(.system(size: SettingsLayout.primaryTextSize))
                    Spacer()
                    Button(language.text(.exportDiagnostics)) { model.exportRecoveryDiagnostics() }
                        .font(.system(size: SettingsLayout.actionTextSize))
                        .controlSize(.small)
                }
                .frame(height: 36)
            }

            SettingsGroup(title: language.text(.lightStatus)) {
                LightStatusList(profile: lightingProfile)
            }

            if let notice = model.aulaNotice {
                SettingsNotice(text: notice, isError: false)
            }
            if let keyboardError = model.keyboardError {
                SettingsNotice(text: keyboardError, isError: true)
            }
            if let agentStateError = model.agentStateError {
                SettingsNotice(text: agentStateError, isError: true)
            }
            if let diagnosticsError = model.diagnosticsError {
                SettingsNotice(text: diagnosticsError, isError: true)
            }
        }
    }

    private var keyboardName: String {
        model.keyboardModel?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? language.text(.compatibleKeyboard)
    }

    private var statusColor: Color {
        if model.aulaNotice != nil { return .orange }
        if model.keyboardError != nil { return .red }
        if model.isDeliveryReady { return .green }
        if model.hidAccessState == .granted { return .orange }
        return .red
    }

    private var statusText: String {
        if let notice = model.aulaNotice { return notice }
        if model.isConnected {
            if model.keyboardError != nil { return language.text(.keyboardSendFailed) }
            if !model.isDeliveryReady { return language.text(.keyboardRecovering) }
            return language.text(lightingProfile == .halo75USB ? .wiredConnected : .bluetoothConnected)
        }
        switch model.hidAccessState {
        case .unknown: return language.text(.checkingKeyboard)
        case .denied: return language.text(.accessRequired)
        case .granted: return language.text(.keyboardNotFound)
        }
    }

    private var lightingProfile: KeyboardLightingProfile {
        KeyboardLightingProfile(productName: model.keyboardModel)
    }
}

enum KeyboardLightingProfile: Equatable {
    case air60Bluetooth
    case halo75Bluetooth
    case halo75USB
    case aulaF99ProBluetooth

    init(productName: String?) {
        guard let productName else {
            self = .air60Bluetooth
            return
        }
        if productName.caseInsensitiveCompare("NuPhy Halo75 V2 NuphyBar") == .orderedSame {
            self = .halo75USB
        } else if productName.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("AULA-F99Pro 5.0") == .orderedSame {
            self = .aulaF99ProBluetooth
        } else if productName.range(
            of: #"^NuPhy Halo75 V2(?:-[1-3])?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            self = .halo75Bluetooth
        } else {
            self = .air60Bluetooth
        }
    }
}

private struct LightStatusList: View {
    @Environment(\.appLanguage) private var language
    let profile: KeyboardLightingProfile

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: 0) {
                switch profile {
                case .halo75USB:
                    row(.thinking, title: language.text(.thinking), detail: language.text(.redBreath), time: time)
                    row(.toolRunning, title: language.text(.toolRunning), detail: language.text(.solidRed), time: time)
                    row(.outputting, title: language.text(.outputting), detail: language.text(.yellowBreath), time: time)
                    row(.permissionRequired, title: language.text(.permissionRequired), detail: language.text(.blueFastBreath), time: time)
                    row(.solidGreen, title: language.text(.taskComplete), detail: language.text(.solidGreen), time: time)
                    row(.error, title: language.text(.error), detail: language.text(.redFlash), time: time)
                case .halo75Bluetooth:
                    row(.thinking, title: language.text(.working), detail: language.text(.redBreath), time: time)
                    row(.permissionRequired, title: language.text(.waiting), detail: language.text(.blueFastBreath), time: time)
                    row(.solidGreen, title: language.text(.taskComplete), detail: language.text(.solidGreen), time: time)
                case .air60Bluetooth:
                    row(.working, title: language.text(.working), detail: language.text(.blueFlow), time: time)
                    row(.waiting, title: language.text(.waiting), detail: language.text(.amberFlash), time: time)
                    row(.complete, title: language.text(.taskComplete), detail: language.text(.greenBreath), time: time)
                case .aulaF99ProBluetooth:
                    row(.toolRunning, title: language.text(.working), detail: language.text(.fullKeyboardRed), time: time)
                    row(.toolRunning, title: language.text(.toolRunning), detail: language.text(.fullKeyboardRed), time: time)
                    row(.solidYellow, title: language.text(.outputting), detail: language.text(.fullKeyboardYellow), time: time)
                    row(.solidBlue, title: language.text(.permissionRequired), detail: language.text(.fullKeyboardBlue), time: time)
                    row(.solidGreen, title: language.text(.taskComplete), detail: language.text(.fullKeyboardGreen), time: time)
                    row(.toolRunning, title: language.text(.error), detail: language.text(.fullKeyboardRed), time: time)
                }
                row(.idle, title: language.text(.idle), detail: language.text(.factoryEffect), time: time)
            }
        }
    }

    private func row(
        _ effect: LightStripEffect,
        title: String,
        detail: String,
        time: TimeInterval
    ) -> some View {
        HStack(spacing: 9) {
            LightStripPreview(
                effect: effect,
                time: time,
                size: CGSize(width: 7, height: 26)
            )
            .frame(width: 18)

            Text(title)
                .font(.system(size: SettingsLayout.primaryTextSize, weight: .regular))

            Spacer()

            Text(detail)
                .font(.system(size: SettingsLayout.secondaryTextSize))
                .foregroundStyle(NuphyBarTheme.secondaryText)
        }
        .frame(height: SettingsLayout.lightRowHeight)
    }
}
