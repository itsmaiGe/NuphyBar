import AgentLightCore
import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            appearance
            Divider()
            integrations
            Divider()
            progressTests
            statusTests

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Light").font(.headline)
                Text(model.connectionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("灯效设置").font(.subheadline.weight(.semibold))
            ColorPicker("颜色", selection: colorBinding, supportsOpacity: false)
            HStack {
                Text("亮度")
                Slider(value: brightnessBinding, in: 0.1...1)
                Text("\(Int(model.preferences.brightness * 100))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
            Stepper(
                "完成呼吸 \(model.preferences.completionDuration) 秒",
                value: durationBinding,
                in: 3...30
            )
            Button("应用到键盘") {
                model.saveAndApplyPreferences()
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isSending)
        }
    }

    private var progressTests: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("五阶段测试").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { stage in
                    Button("\(stage)") {
                        model.send(.progress(UInt8(stage)))
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var integrations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent 接入").font(.subheadline.weight(.semibold))
            integrationRow(.codex, name: "Codex")
            integrationRow(.claudeCode, name: "Claude Code")
            integrationRow(.openCode, name: "OpenCode")
            Text("接入变更将在重启对应 Agent 后生效")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func integrationRow(_ provider: AgentProvider, name: String) -> some View {
        let status = model.integrationStatuses[provider] ?? .unavailable
        return HStack {
            Text(name)
            Spacer()
            switch status {
            case .unavailable:
                Text("未检测到").foregroundStyle(.secondary)
            case .available:
                Button("接入") { model.toggleIntegration(provider) }
                    .buttonStyle(.bordered)
            case .installed:
                Button("已接入 · 移除") { model.toggleIntegration(provider) }
                    .buttonStyle(.bordered)
            }
        }
        .font(.caption)
    }

    private var statusTests: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("状态测试").font(.subheadline.weight(.semibold))
            HStack {
                statusButton("工作", icon: "bolt.fill", command: .working)
                statusButton("等待", icon: "exclamationmark.circle", command: .waiting)
                statusButton("完成", icon: "checkmark.circle", command: .complete)
                statusButton("错误", icon: "xmark.circle", command: .error)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("重新检测") { model.refreshConnection() }
            Button("恢复原灯效") { model.send(.idle) }
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func statusButton(_ title: String, icon: String, command: AgentLightCommand) -> some View {
        Button {
            model.send(command)
        } label: {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .help(title)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .disabled(model.isSending)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(rgb: model.preferences.color) },
            set: { color in
                if let rgb = color.rgbColor { model.preferences.color = rgb }
            }
        )
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { model.preferences.brightness },
            set: { model.preferences.brightness = $0 }
        )
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { Int(model.preferences.completionDuration) },
            set: { model.preferences.completionDuration = UInt8($0) }
        )
    }
}
