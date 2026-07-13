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
            }

            SettingsGroup(title: language.text(.lightStatus)) {
                LightStatusList()
            }

            if let keyboardError = model.keyboardError {
                SettingsNotice(text: keyboardError, isError: true)
            }
        }
    }

    private var keyboardName: String {
        model.keyboardModel ?? language.text(.nuphyKeyboard)
    }

    private var statusColor: Color {
        if model.isConnected { return .green }
        if model.hidAccessState == .granted { return .orange }
        return .red
    }

    private var statusText: String {
        if model.isConnected { return language.text(.bluetoothConnected) }
        switch model.hidAccessState {
        case .unknown: return language.text(.checkingKeyboard)
        case .denied: return language.text(.accessRequired)
        case .granted: return language.text(.keyboardNotFound)
        }
    }
}

private struct LightStatusList: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: 0) {
                row(.working, title: language.text(.working), detail: language.text(.blueFlow), time: time)
                row(.waiting, title: language.text(.waiting), detail: language.text(.amberFlash), time: time)
                row(.complete, title: language.text(.taskComplete), detail: language.text(.greenBreath), time: time)
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
