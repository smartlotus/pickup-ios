import PickupCore
import SwiftUI

public struct SettingsView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var showPassphraseAlert = false
    @State private var newPassphrase = ""

    public var body: some View {
        let p = store.palette
        let s = store.strings
        let isZh = store.preferences.language == .zh

        NavigationStack {
            Form {
                Section(s.t("theme_title")) {
                    Picker(s.t("theme_title"), selection: Binding(
                        get: { store.preferences.themeStyle },
                        set: { val in Task { await store.updatePreferences { $0.themeStyle = val } } }
                    )) {
                        Text(s.t("theme_mono")).tag(PickupThemeStyle.monochrome)
                        Text(s.t("theme_mono_light")).tag(PickupThemeStyle.monochromeLight)
                    }

                    Picker(s.t("typography_title"), selection: Binding(
                        get: { store.preferences.typographyStyle },
                        set: { val in Task { await store.updatePreferences { $0.typographyStyle = val } } }
                    )) {
                        Text(s.t("typo_serif")).tag(PickupTypographyStyle.editorialSerif)
                        Text(s.t("typo_sans")).tag(PickupTypographyStyle.cleanSans)
                    }

                    Picker(s.t("language_title"), selection: Binding(
                        get: { store.preferences.language },
                        set: { val in Task { await store.updatePreferences { $0.language = val } } }
                    )) {
                        Text("中文").tag(PickupLanguage.zh)
                        Text("English").tag(PickupLanguage.en)
                    }

                    Toggle(s.t("skip_intro"), isOn: Binding(
                        get: { store.preferences.skipLaunchIntro },
                        set: { val in Task { await store.updatePreferences { $0.skipLaunchIntro = val } } }
                    ))
                }

                Section(s.t("privacy_lock")) {
                    Toggle("Face ID / Touch ID", isOn: Binding(
                        get: { store.preferences.biometricLockEnabled },
                        set: { val in Task { await store.updatePreferences { $0.biometricLockEnabled = val } } }
                    ))

                    Button {
                        showPassphraseAlert = true
                    } label: {
                        HStack {
                            Text(store.preferences.isPassphraseLockEnabled ? (isZh ? "修改独立隐私口令" : "Change Passphrase Lock") : (isZh ? "设置独立隐私口令" : "Set Passphrase Lock"))
                            Spacer()
                            if store.preferences.isPassphraseLockEnabled {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(p.accent)
                            }
                        }
                    }

                    if store.preferences.isPassphraseLockEnabled {
                        Button(isZh ? "移除口令锁" : "Remove Passphrase Lock", role: .destructive) {
                            Task {
                                await store.updatePreferences {
                                    $0.passphraseLockSaltBase64 = nil
                                    $0.passphraseLockHashBase64 = nil
                                }
                            }
                        }
                    }
                }

                Section(s.t("sideload_guide")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isZh
                             ? "本应用专为无付费 Apple 开发者账号 ($99/年) 的侧载用户设计："
                             : "Designed specifically for free Apple ID sideloading without a $99/yr Developer account:")
                            .font(.subheadline.weight(.semibold))
                        Text(isZh
                             ? "1. 推荐使用 SideStore 或 AltStore 在 Wi-Fi 下每 7 天自动续签一次。\n2. 请前往「数据」标签页开启每日自动备份，并绑定外部文件夹（如「文件」App 或局域网 NAS），即使免费签名意外过期，记忆也 100% 不丢失。\n3. 导出的 .zip 备份可与 Pickup Android / Web v2 无损互通。"
                             : "1. Use SideStore or AltStore for wireless 7-day auto-refresh.\n2. Enable Daily Auto-Backup and link an external folder in the Data Vault tab so memories survive even if a free signing cert expires.\n3. Exported .zip files are 100% compatible with Pickup Android & Web v2.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    HStack {
                        Text("Pickup for iOS & iPadOS")
                        Spacer()
                        Text("v1.0.0 · 渚有潜")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle(s.t("settings_title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(s.t("done")) { dismiss() }
                }
            }
        }
        .alert(isZh ? "设置本地隐私口令" : "Set Local Lock Passphrase", isPresented: $showPassphraseAlert) {
            SecureField(isZh ? "新口令" : "New passphrase", text: $newPassphrase)
            Button(s.t("cancel"), role: .cancel) { newPassphrase = "" }
            Button(s.t("save")) {
                let raw = newPassphrase
                newPassphrase = ""
                if let hashed = try? VaultCrypto.hashPassphraseForLock(raw) {
                    Task {
                        await store.updatePreferences {
                            $0.passphraseLockSaltBase64 = hashed.saltBase64
                            $0.passphraseLockHashBase64 = hashed.hashBase64
                        }
                    }
                }
            }
        }
    }
}
