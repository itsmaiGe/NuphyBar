import AgentLightCore
import SwiftUI

struct AgentSettingsView: View {
    @Environment(\.appLanguage) private var language
    @Bindable var model: AppModel

    var body: some View {
        SettingsPage {
            SettingsGroup(title: language.text(.agentIntegrations)) {
                VStack(spacing: 0) {
                    integrationRow(.codex)
                    integrationRow(.claudeCode)
                    integrationRow(.antigravity)
                    integrationRow(.openCode)
                    integrationRow(.grokBuild)
                    integrationRow(.hermes)
                    integrationRow(.openClaw)
                }
            }

            if model.integrationStatuses[.codex] == .needsReview {
                SettingsNotice(text: language.text(.codexApprovalRequired))
            } else if let provider = model.integrationNoticeProvider {
                SettingsNotice(text: language.integrationSaved(providerName: provider.displayName))
            }

            if let integrationError = model.integrationError {
                SettingsNotice(text: integrationError, isError: true)
            }
        }
    }

    private func integrationRow(_ provider: AgentProvider) -> some View {
        let status = model.integrationStatuses[provider] ?? .unavailable

        return HStack(spacing: 9) {
            AgentBrandIcon(provider: provider, size: 18)
                .frame(width: 24, height: 24)

            Text(provider.displayName)
                .font(.system(size: SettingsLayout.primaryTextSize, weight: .regular))

            Spacer()
            integrationAction(provider, status: status)
        }
        .frame(height: SettingsLayout.agentRowHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func integrationAction(_ provider: AgentProvider, status: IntegrationStatus) -> some View {
        switch status {
        case .unavailable:
            Text(language.text(.unavailable))
                .font(.system(size: SettingsLayout.actionTextSize))
                .foregroundStyle(NuphyBarTheme.tertiaryText)
        case .available:
            Button(language.text(.connect)) { model.toggleIntegration(provider) }
                .font(.system(size: SettingsLayout.actionTextSize))
                .controlSize(.small)
        case .needsReview:
            HStack(spacing: 8) {
                Text(language.text(.pending))
                    .font(.system(size: SettingsLayout.actionTextSize))
                    .foregroundStyle(NuphyBarTheme.accent)
                Button(language.text(.remove)) { model.toggleIntegration(provider) }
                    .font(.system(size: SettingsLayout.actionTextSize))
                    .controlSize(.small)
            }
        case .installed:
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(language.text(.connected))
                    .font(.system(size: SettingsLayout.actionTextSize))
                    .foregroundStyle(NuphyBarTheme.secondaryText)
                Button(language.text(.remove)) { model.toggleIntegration(provider) }
                    .font(.system(size: SettingsLayout.actionTextSize))
                    .controlSize(.small)
            }
        }
    }
}

extension AgentProvider {
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .openCode: "OpenCode"
        case .grokBuild: "Grok Build"
        case .hermes: "Hermes"
        case .openClaw: "OpenClaw"
        case .antigravity: "Antigravity"
        }
    }
}
