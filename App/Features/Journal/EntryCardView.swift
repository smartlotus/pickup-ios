import PickupCore
import SwiftUI

public struct EntryCardView: View {
    let store: AppStore
    let entry: CapsuleEntry
    let onEdit: () -> Void
    let onInspectMedia: (MediaAttachment) -> Void

    @State private var showQuickReply = false
    @State private var quickReplyText = ""

    public var body: some View {
        let p = store.palette
        let isZh = store.preferences.language == .zh
        PickupEditorialCard(palette: p, cornerRadius: 22, padding: 18, isPinned: entry.isPinned) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(p.tertiaryText)

                    if let mood = entry.mood {
                        Text(mood)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(p.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(p.accent.opacity(0.14), in: Capsule())
                    }

                    if let weather = entry.weather {
                        Text(weather)
                            .font(.caption2)
                            .foregroundStyle(p.secondaryText)
                    }

                    Spacer()

                    Button {
                        Task { await store.togglePin(entry: entry) }
                    } label: {
                        Image(systemName: entry.isPinned ? "star.fill" : "star")
                            .font(.subheadline)
                            .foregroundStyle(entry.isPinned ? p.accent : p.tertiaryText)
                    }

                    Button(action: onEdit) {
                        Image(systemName: "ellipsis.circle")
                            .font(.subheadline)
                            .foregroundStyle(p.secondaryText)
                    }
                }

                if let song = entry.songInfo, !song.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(p.accent)
                        Text(song)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(p.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(p.elevatedSurface, in: Capsule())
                }

                if !entry.content.isEmpty {
                    Text(entry.content)
                        .font(p.bodyFont(size: 16))
                        .lineSpacing(5)
                        .foregroundStyle(p.primaryText)
                }

                if !entry.media.isEmpty {
                    MediaAttachmentStrip(store: store, attachments: entry.media, onTap: onInspectMedia)
                }

                if !entry.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(entry.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption2)
                                    .foregroundStyle(p.secondaryText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(p.elevatedSurface, in: Capsule())
                            }
                        }
                    }
                }

                if !entry.comments.isEmpty {
                    Divider().overlay(p.hairline)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(entry.comments) { comment in
                            HStack(alignment: .top, spacing: 8) {
                                Rectangle()
                                    .fill(p.redPen)
                                    .frame(width: 2)
                                    .clipShape(Capsule())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(comment.text)
                                        .font(.subheadline)
                                        .foregroundStyle(p.primaryText.opacity(0.92))
                                    Text(comment.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(p.tertiaryText)
                                }
                            }
                        }
                    }
                }

                HStack {
                    Button {
                        withAnimation(.spring(response: 0.3)) { showQuickReply.toggle() }
                    } label: {
                        Label(isZh ? "写一句回看" : "Reply", systemImage: "bubble.left.and.text.bubble.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(p.secondaryText)
                    }
                    Spacer()
                }

                if showQuickReply {
                    HStack(spacing: 8) {
                        TextField(store.strings.t("reflection_hint"), text: $quickReplyText)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(p.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                        Button {
                            let text = quickReplyText
                            quickReplyText = ""
                            showQuickReply = false
                            Task { await store.addReflection(to: entry, text: text) }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(p.accent)
                        }
                        .disabled(quickReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}
