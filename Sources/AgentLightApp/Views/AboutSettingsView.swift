import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @Environment(\.appLanguage) private var language
    @Binding var languageRawValue: String
    @State private var launchAtLoginStatus = LaunchAtLoginStatus.disabled
    @State private var launchAtLoginError: String?

    private let launchAtLogin = LaunchAtLoginController()

    var body: some View {
        VStack(spacing: SettingsLayout.aboutSectionSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(language.text(.language))
                        .font(.system(size: SettingsLayout.primaryTextSize))

                    Spacer()

                    Picker("", selection: $languageRawValue) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.nativeName).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 120)
                }
                .frame(height: SettingsLayout.aboutRowHeight)

                HStack(spacing: 12) {
                    Text(language.text(.launchAtLogin))
                        .font(.system(size: SettingsLayout.primaryTextSize))

                    Spacer()

                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .frame(height: SettingsLayout.aboutRowHeight)

                if launchAtLoginStatus == .requiresApproval {
                    Text(language.text(.launchAtLoginApproval))
                        .font(.system(size: SettingsLayout.secondaryTextSize))
                        .foregroundStyle(NuphyBarTheme.secondaryText)
                } else if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.system(size: SettingsLayout.secondaryTextSize))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: SettingsLayout.aboutContentWidth)

            VStack(spacing: 4) {
                Text("NuphyBar \(appVersion)")
                    .font(.system(size: 13, weight: .semibold))
                Text(language.text(.aboutDescription))
                    .font(.system(size: SettingsLayout.secondaryTextSize))
                    .foregroundStyle(NuphyBarTheme.secondaryText)

                Link(language.text(.followOnX), destination: URL(string: "https://x.com/unflwMaige")!)
                    .font(.system(size: SettingsLayout.secondaryTextSize))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            launchAtLoginStatus = launchAtLogin.status
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLoginStatus = launchAtLogin.status
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                launchAtLoginStatus.isOn
            },
            set: { enabled in
                do {
                    try launchAtLogin.setEnabled(enabled)
                    launchAtLoginStatus = launchAtLogin.status
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginStatus = launchAtLogin.status
                    launchAtLoginError = "\(language.text(.launchAtLoginFailed)) \(error.localizedDescription)"
                }
            }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.8"
    }
}
