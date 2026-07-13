import Testing
@testable import AgentLightApp

@Test("the in-app language covers both settings languages")
func appLanguageProvidesChineseAndEnglishCopy() {
    #expect(AppLanguage.simplifiedChinese.nativeName == "简体中文")
    #expect(AppLanguage.english.nativeName == "English")
    #expect(AppLanguage.simplifiedChinese.text(.connect) == "接入")
    #expect(AppLanguage.english.text(.connect) == "Connect")
    #expect(AppLanguage.simplifiedChinese.text(.launchAtLogin) == "开机时自动启动")
    #expect(AppLanguage.english.text(.launchAtLogin) == "Launch at Login")
    #expect(SettingsSection.keyboard.title(in: .english) == "Keyboard")
    #expect(SettingsSection.about.title(in: .simplifiedChinese) == "关于")
}
