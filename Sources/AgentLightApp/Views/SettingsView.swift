import SwiftUI

enum SettingsLayout {
    static let windowWidth: CGFloat = 440
    static let windowHeight: CGFloat = 330
    static let tabWidth: CGFloat = 56
    static let tabHeight: CGFloat = 48
    static let horizontalPadding: CGFloat = 18
    static let sectionTitleSize: CGFloat = 11.5
    static let primaryTextSize: CGFloat = 12.5
    static let secondaryTextSize: CGFloat = 9.5
    static let actionTextSize: CGFloat = 12
    static let agentRowHeight: CGFloat = 36
    static let lightRowHeight: CGFloat = 34
    static let aboutContentWidth: CGFloat = 280
    static let aboutRowHeight: CGFloat = 28
    static let aboutSectionSpacing: CGFloat = 24
}

enum SettingsSection: Hashable, CaseIterable {
    case agents
    case keyboard
    case about

    func title(in language: AppLanguage) -> String {
        switch self {
        case .agents: language.text(.agentTab)
        case .keyboard: language.text(.keyboardTab)
        case .about: language.text(.aboutTab)
        }
    }

    var systemImage: String {
        switch self {
        case .agents: "point.3.connected.trianglepath.dotted"
        case .keyboard: "keyboard"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.simplifiedChinese.rawValue
    @State private var selection: SettingsSection

    init(model: AppModel, selection: SettingsSection = .agents) {
        self.model = model
        _selection = State(initialValue: selection)
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selection: $selection)
                .padding(.top, 4)
                .padding(.bottom, 6)

            Divider()

            Group {
                switch selection {
                case .agents:
                    AgentSettingsView(model: model)
                case .keyboard:
                    KeyboardSettingsView(model: model)
                case .about:
                    AboutSettingsView(languageRawValue: $languageRawValue)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
        .foregroundStyle(NuphyBarTheme.text)
        .tint(NuphyBarTheme.accent)
        .background(NuphyBarTheme.background)
        .environment(\.appLanguage, language)
        .environment(\.locale, language.locale)
        .onChange(of: languageRawValue) {
            NotificationCenter.default.post(name: .nuphyBarLanguageDidChange, object: nil)
        }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }
}

private struct SettingsTabBar: View {
    @Environment(\.appLanguage) private var language
    @Binding var selection: SettingsSection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                Button {
                    selection = section
                } label: {
                    VStack(spacing: 1.5) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 20, weight: .regular))
                            .frame(height: 22)
                        Text(section.title(in: language))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(selection == section ? NuphyBarTheme.accent : NuphyBarTheme.secondaryText)
                    .frame(width: SettingsLayout.tabWidth, height: SettingsLayout.tabHeight)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title(in: language))
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
    }
}

struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.horizontal, SettingsLayout.horizontalPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: SettingsLayout.sectionTitleSize, weight: .medium))
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
    }
}

struct SettingsNotice: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(.system(size: SettingsLayout.secondaryTextSize))
            .foregroundStyle(isError ? Color.red : NuphyBarTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (isError ? Color.red : NuphyBarTheme.accent).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }
}
