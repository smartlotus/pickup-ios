import PickupCore
import SwiftUI

public struct OnboardingView: View {
    let store: AppStore
    @State private var page = 0

    private var steps: [(icon: String, titleZh: String, titleEn: String, bodyZh: String, bodyEn: String)] {
        [
            ("book.closed.fill", "把微小的日常，拾起来", "Keep the little things", "文字、照片、Live Photo 实况与此刻正在听的歌，全部安全保存在本机。", "Words, Live Photos, video, and your soundtrack right now—stored strictly on your device."),
            ("calendar.circle.fill", "红笔圈起走过的日子", "Return to any day", "月历红笔圈出有记忆的日期，在「去留」中偶遇过去的自己并写下今日回应。", "Red ink circles every recorded day. Meet your past self in Revisit and reply from today."),
            ("brain.head.profile.fill", "克制而透明的 AI 回忆", "Consent-first AI Hub", "只在你确认披露预览后才发送筛选的文字范围，绝不上传任何照片与视频。", "Requests send only the text range you approve beforehand. Media never leaves your device."),
            ("externaldrive.badge.timemachine", "自动定时本地备份", "Scheduled Local Vault", "无需每年 $99 开发者费用，支持自动备份至外部文件夹、加密导出与安卓/Web 双向互通。", "Zero developer fee needed. Auto-backup to Files/iCloud/NAS and migrate seamlessly with Android/Web."),
        ]
    }

    public var body: some View {
        let p = store.palette
        let isZh = store.preferences.language == .zh
        ZStack {
            PickupAmbientBackdrop(palette: p)

            VStack(spacing: 24) {
                HStack {
                    Spacer()
                    Button(store.strings.t("tutorial_skip")) {
                        Task { await finish() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(p.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .pickupGlassCapsule()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                        VStack(alignment: .leading, spacing: 20) {
                            ZStack {
                                Circle()
                                    .strokeBorder(p.redPen.opacity(0.65), lineWidth: 1.5)
                                    .frame(width: 64, height: 64)
                                Image(systemName: step.icon)
                                    .font(.title2)
                                    .foregroundStyle(p.accent)
                            }

                            Text(isZh ? step.titleZh : step.titleEn)
                                .font(p.editorialFont(size: 28, weight: .bold, typography: store.preferences.typographyStyle))
                                .foregroundStyle(p.primaryText)

                            Text(isZh ? step.bodyZh : step.bodyEn)
                                .font(.body)
                                .lineSpacing(6)
                                .foregroundStyle(p.secondaryText)

                            Spacer()

                            HStack {
                                Text("\(idx + 1) / \(steps.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(p.tertiaryText)
                                Spacer()
                                AnimatedRedPenMark(color: p.redPen, animate: page == idx)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        .padding(28)
                        .frame(maxWidth: 520, maxHeight: 400)
                        .pickupGlassRect(cornerRadius: 28, interactive: false)
                        .padding(.horizontal, 24)
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                PickupGlassGroup(spacing: 14) {
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            ForEach(0..<steps.count, id: \.self) { idx in
                                Capsule()
                                    .fill(idx == page ? p.accent : p.hairline)
                                    .frame(width: idx == page ? 24 : 8, height: 8)
                                    .animation(.spring(response: 0.3), value: page)
                            }
                        }

                        Spacer()

                        Button {
                            if page < steps.count - 1 {
                                withAnimation(.spring(response: 0.38)) { page += 1 }
                            } else {
                                Task { await finish() }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(store.strings.t(page == steps.count - 1 ? "tutorial_start" : "tutorial_next"))
                                Image(systemName: "arrow.right")
                            }
                            .font(.headline)
                            .foregroundStyle(p.tintButtonForeground)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 14)
                            .pickupGlassCapsule(tint: p.accent, interactive: true)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private func finish() async {
        await store.updatePreferences { $0.tutorialCompleted = true }
        await store.checkDailyRevisitAfterLaunch()
    }
}
