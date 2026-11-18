import PickupCore
import SwiftUI

public struct HomeFeedView: View {
    @Bindable var store: AppStore
    let onNewEntry: () -> Void
    let onEditEntry: (CapsuleEntry) -> Void
    let onOpenSettings: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var inspectedMedia: MediaAttachment? = nil
    @State private var inspectedEntryMedia: [MediaAttachment] = []

    public var body: some View {
        let p = store.palette
        let s = store.strings
        let isZh = store.preferences.language == .zh
        let list = store.filteredEntries

        ZStack {
            PickupAmbientBackdrop(palette: p)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroHeader(palette: p, isZh: isZh)
                    filterStrip(palette: p, strings: s)

                    if !store.allTags.isEmpty {
                        tagStrip(palette: p, isZh: isZh)
                    }

                    if list.isEmpty {
                        emptyState(palette: p, strings: s)
                    } else if sizeClass == .regular {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 16, alignment: .top)], spacing: 16) {
                            ForEach(list) { entry in
                                EntryCardView(
                                    store: store,
                                    entry: entry,
                                    onEdit: { onEditEntry(entry) },
                                    onInspectMedia: { att in
                                        inspectedEntryMedia = entry.media
                                        inspectedMedia = att
                                    }
                                )
                            }
                        }
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(list) { entry in
                                EntryCardView(
                                    store: store,
                                    entry: entry,
                                    onEdit: { onEditEntry(entry) },
                                    onInspectMedia: { att in
                                        inspectedEntryMedia = entry.media
                                        inspectedMedia = att
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 128)
            }
        }
        .navigationTitle("Pickup")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $store.searchQuery, prompt: Text(s.t("search_hint")))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task {
                        await store.updatePreferences {
                            $0.themeStyle = ($0.themeStyle == .monochrome) ? .monochromeLight : .monochrome
                        }
                    }
                } label: {
                    Image(systemName: store.preferences.themeStyle == .monochrome ? "circle.lefthalf.filled" : "sun.max")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    store.selectedTab = .data
                } label: {
                    Image(systemName: "externaldrive.badge.timemachine")
                }
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .fullScreenCover(item: $inspectedMedia) { item in
            MediaViewerSheet(store: store, attachments: inspectedEntryMedia, initialAttachment: item)
        }
    }

    private func heroHeader(palette p: PickupPalette, isZh: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(isZh ? "把日子，" : "Keep the ")
                        .font(p.editorialFont(size: 28, weight: .bold, typography: store.preferences.typographyStyle))
                        .foregroundStyle(p.primaryText)

                    if isZh {
                        ZStack {
                            Text("拾")
                                .font(p.editorialFont(size: 28, weight: .bold, typography: store.preferences.typographyStyle))
                                .foregroundStyle(p.primaryText)
                            AnimatedRedPenMark(color: p.redPen, lineWidth: 2.0, animate: true)
                                .frame(width: 40, height: 40)
                        }
                        Text("起来。")
                            .font(p.editorialFont(size: 28, weight: .bold, typography: store.preferences.typographyStyle))
                            .foregroundStyle(p.primaryText)
                    } else {
                        Text("little things.")
                            .font(p.editorialFont(size: 28, weight: .bold, typography: store.preferences.typographyStyle))
                            .foregroundStyle(p.accent)
                    }
                }

                HStack(spacing: 10) {
                    Label("\(store.entries.count)", systemImage: "book.pages")
                    Text("·")
                    Label("\(store.streakDays)d", systemImage: "flame.fill")
                        .foregroundStyle(store.streakDays > 0 ? p.redPen : p.secondaryText)
                    if let last = store.preferences.autoBackup.lastSuccessAt {
                        Text("·")
                        Label(
                            last.formatted(date: .omitted, time: .shortened),
                            systemImage: "checkmark.shield"
                        )
                        .foregroundStyle(p.accent)
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(p.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func filterStrip(palette p: PickupPalette, strings s: PickupStrings) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            PickupGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(JournalFilter.allCases, id: \.self) { filter in
                        let selected = store.activeFilter == filter
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                store.activeFilter = filter
                            }
                        } label: {
                            Text(s.t("filter_\(filter.rawValue)"))
                                .font(.subheadline.weight(selected ? .bold : .medium))
                                .foregroundStyle(selected ? p.tintButtonForeground : p.secondaryText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .pickupGlassCapsule(
                                    tint: selected ? p.accent : nil,
                                    interactive: true,
                                    fallbackSurface: selected ? p.accent : p.glassFill
                                )
                        }
                    }
                }
            }
        }
    }

    private func tagStrip(palette p: PickupPalette, isZh: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.allTags, id: \.self) { tag in
                    let active = store.selectedTag == tag
                    Button {
                        withAnimation(.spring(response: 0.28)) {
                            store.selectedTag = active ? nil : tag
                        }
                    } label: {
                        Text("#\(tag)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(active ? p.tintButtonForeground : p.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(active ? p.accent : p.glassFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(active ? p.accent : p.hairline, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func emptyState(palette p: PickupPalette, strings s: PickupStrings) -> some View {
        PickupEditorialCard(palette: p, cornerRadius: 24, padding: 26) {
            VStack(spacing: 14) {
                AnimatedRedPenMark(color: p.redPen, animate: true)
                    .frame(width: 44, height: 44)
                Text(s.t("journal_empty_title"))
                    .font(p.editorialFont(size: 20, weight: .semibold, typography: store.preferences.typographyStyle))
                    .foregroundStyle(p.primaryText)
                Text(s.t("journal_empty_body"))
                    .font(.subheadline)
                    .foregroundStyle(p.secondaryText)
                    .multilineTextAlignment(.center)
                Button(action: onNewEntry) {
                    Label(s.t("new_entry"), systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(p.tintButtonForeground)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .pickupGlassCapsule(tint: p.accent, interactive: true)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
