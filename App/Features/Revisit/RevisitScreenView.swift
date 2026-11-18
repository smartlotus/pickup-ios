import PickupCore
import SwiftUI

public struct RevisitScreenView: View {
    @Bindable var store: AppStore
    let onOpenSettings: () -> Void
    @State private var currentEntry: CapsuleEntry? = nil

    public var body: some View {
        let s = store.strings
        RevisitEntryDetailView(
            store: store,
            initialEntry: currentEntry ?? store.entries.first,
            isDailyModal: false,
            onOpenSettings: onOpenSettings
        )
        .navigationTitle(s.t("tab_revisit"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if currentEntry == nil {
                currentEntry = try? await store.revisitService.randomEntry(excludingId: nil)
            }
        }
    }
}

public struct RevisitEntryDetailView: View {
    @Bindable var store: AppStore
    let initialEntry: CapsuleEntry?
    let isDailyModal: Bool
    var onOpenSettings: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var activeEntry: CapsuleEntry? = nil
    @State private var replyText: String = ""
    @State private var flipTrigger = false
    @State private var inspectedMedia: MediaAttachment? = nil

    public var body: some View {
        let p = store.palette
        let s = store.strings
        let isZh = store.preferences.language == .zh
        let shown = activeEntry ?? initialEntry

        ZStack {
            PickupAmbientBackdrop(palette: p)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isDailyModal {
                        HStack {
                            Label(s.t("revisit_daily_badge"), systemImage: "sparkles")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(p.highlight)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .pickupGlassCapsule(interactive: false)
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 34, height: 34)
                                    .pickupGlassCircle()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(isZh ? "与过去的自己偶遇" : "Meet your past self")
                            .font(p.editorialFont(size: 26, weight: .bold, typography: store.preferences.typographyStyle))
                            .foregroundStyle(p.primaryText)
                        Text(isZh ? "读一读当时的心境，再留下一句此刻的回音。" : "Read who you were then, and leave a reply from today.")
                            .font(.subheadline)
                            .foregroundStyle(p.secondaryText)
                    }

                    if let entry = shown {
                        PickupEditorialCard(palette: p, cornerRadius: 26, padding: 22, isPinned: true) {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(entry.timestamp.formatted(date: .long, time: .shortened))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(p.highlight)
                                    Spacer()
                                    if let mood = entry.mood {
                                        Text(mood)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(p.accent)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(p.accent.opacity(0.15), in: Capsule())
                                    }
                                }

                                if let song = entry.songInfo {
                                    Label(song, systemImage: "music.note")
                                        .font(.caption)
                                        .foregroundStyle(p.secondaryText)
                                }

                                Text(entry.content)
                                    .font(p.editorialFont(size: 18, weight: .regular, typography: store.preferences.typographyStyle))
                                    .lineSpacing(7)
                                    .foregroundStyle(p.primaryText)

                                if !entry.media.isEmpty {
                                    MediaAttachmentStrip(store: store, attachments: entry.media) { att in
                                        inspectedMedia = att
                                    }
                                }

                                if !entry.comments.isEmpty {
                                    Divider().overlay(p.hairline)
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(s.t("reflections_title"))
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(p.tertiaryText)
                                        ForEach(entry.comments) { comment in
                                            HStack(alignment: .top, spacing: 8) {
                                                Rectangle().fill(p.redPen).frame(width: 2)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(comment.text)
                                                        .font(.subheadline)
                                                        .foregroundStyle(p.primaryText)
                                                    Text(comment.timestamp.formatted(date: .abbreviated, time: .shortened))
                                                        .font(.caption2.monospacedDigit())
                                                        .foregroundStyle(p.tertiaryText)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .rotation3DEffect(.degrees(flipTrigger ? 6 : 0), axis: (x: 0, y: 1, z: 0))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: flipTrigger)

                        // Reply box
                        PickupGlassGroup(spacing: 10) {
                            HStack(spacing: 10) {
                                TextField(s.t("reflection_hint"), text: $replyText)
                                    .padding(14)
                                    .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(p.hairline))

                                Button {
                                    let clean = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !clean.isEmpty else { return }
                                    replyText = ""
                                    Task {
                                        if let updated = try? await store.revisitService.writeBackResponse(entry: entry, text: clean) {
                                            activeEntry = updated
                                            await store.reloadAll()
                                            store.showToast(isZh ? "回应已写回原日记" : "Reply saved to entry")
                                        }
                                    }
                                } label: {
                                    Image(systemName: "paperplane.fill")
                                        .font(.headline)
                                        .foregroundStyle(p.tintButtonForeground)
                                        .frame(width: 48, height: 48)
                                        .pickupGlassCircle(tint: p.accent, interactive: true)
                                }
                            }
                        }

                        Button {
                            shuffleMemory(currentId: entry.id)
                        } label: {
                            Label(s.t("revisit_shuffle"), systemImage: "shuffle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(p.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .pickupGlassCapsule(interactive: true)
                        }
                        .sensoryFeedback(.impact(flexibility: .soft), trigger: flipTrigger)
                    } else {
                        PickupEditorialCard(palette: p, cornerRadius: 22, padding: 24) {
                            Text(s.t("revisit_empty"))
                                .font(.subheadline)
                                .foregroundStyle(p.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 96)
            }
        }
        .toolbar {
            if let onOpenSettings {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenSettings) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .fullScreenCover(item: $inspectedMedia) { item in
            MediaViewerSheet(store: store, attachments: shown?.media ?? [item], initialAttachment: item)
        }
        .onAppear {
            if activeEntry == nil { activeEntry = initialEntry }
        }
    }

    private func shuffleMemory(currentId: String) {
        flipTrigger.toggle()
        Task {
            if let next = try? await store.revisitService.randomEntry(excludingId: currentId) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    activeEntry = next
                }
            }
        }
    }
}
