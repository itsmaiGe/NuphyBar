import Testing
@testable import AgentLightApp

@Test("launch at login treats pending user approval as switched on")
func launchAtLoginStatusPresentation() {
    #expect(LaunchAtLoginStatus.enabled.isOn)
    #expect(LaunchAtLoginStatus.requiresApproval.isOn)
    #expect(!LaunchAtLoginStatus.disabled.isOn)
    #expect(!LaunchAtLoginStatus.unavailable.isOn)
}
