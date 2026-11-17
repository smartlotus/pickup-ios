import PickupCore
import SwiftUI

public struct PrivacyLockView: View {
    let store: AppStore
    @State private var passphrase = ""
    @State private var errorMsg: String? = nil

    public var body: some View {
        let p = store.palette
        let isZh = store.preferences.language == .zh
        ZStack {
            PickupAmbientBackdrop(palette: p)

            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(p.accent)

                Text(isZh ? "解锁 Pickup 隐私空间" : "Unlock Pickup Vault")
                    .font(p.editorialFont(size: 24, weight: .bold, typography: store.preferences.typographyStyle))
                    .foregroundStyle(p.primaryText)

                Text(isZh ? "所有日记均留在本机，口令绝不会上传至网络。" : "Your memories live locally; your passphrase never leaves this device.")
                    .font(.footnote)
                    .foregroundStyle(p.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                if store.preferences.isPassphraseLockEnabled {
                    SecureField(isZh ? "输入隐私锁口令" : "Enter privacy passphrase", text: $passphrase)
                        .textFieldStyle(.plain)
                        .padding(14)
                        .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(p.hairline))
                        .frame(maxWidth: 340)
                        .onSubmit { verifyPassphrase() }

                    Button(action: verifyPassphrase) {
                        Text(isZh ? "解锁" : "Unlock")
                            .font(.headline)
                            .foregroundStyle(p.tintButtonForeground)
                            .frame(maxWidth: 340)
                            .padding(.vertical, 14)
                            .pickupGlassCapsule(tint: p.accent, interactive: true)
                    }
                }

                if store.preferences.biometricLockEnabled {
                    Button {
                        Task {
                            let ok = await store.attemptBiometricUnlock()
                            if !ok {
                                errorMsg = isZh ? "面容 / 触控认证未通过" : "Biometric verification failed"
                            }
                        }
                    } label: {
                        Label(isZh ? "使用 Face ID / Touch ID 解锁" : "Unlock with Face ID / Touch ID", systemImage: "faceid")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(p.primaryText)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .pickupGlassCapsule()
                    }
                }

                if let errorMsg {
                    Text(errorMsg)
                        .font(.footnote)
                        .foregroundStyle(p.redPen)
                }
            }
            .padding(28)
        }
        .task {
            if store.preferences.biometricLockEnabled {
                _ = await store.attemptBiometricUnlock()
            }
        }
    }

    private func verifyPassphrase() {
        guard let salt = store.preferences.passphraseLockSaltBase64,
              let hash = store.preferences.passphraseLockHashBase64 else {
            store.isLocked = false
            return
        }
        if VaultCrypto.verifyPassphraseForLock(passphrase, saltBase64: salt, hashBase64: hash) {
            store.isLocked = false
            Task { await store.checkDailyRevisitAfterLaunch() }
        } else {
            errorMsg = store.preferences.language == .zh ? "口令不正确" : "Incorrect passphrase"
        }
    }
}
