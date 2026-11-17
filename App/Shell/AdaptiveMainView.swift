import PickupCore
import SwiftUI

public struct AdaptiveMainView: View {
    @Bindable var store: AppStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var glassNS

    @State private var showEditor = false
    @State private var editorTargetEntry: CapsuleEntry? = nil
    @State private var showSettings = false
    @State private var quickMenuExpanded = false
    @State private var showQuickSketch = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(store: AppStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if sizeClass == .regular {
                iPadSplitShell
            } else {
                iPhoneTabShell
            }
        }
        .sheet(isPresented: $showEditor) {
            RichEditorView(store: store, existingEntry: editorTargetEntry)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: store)
        }
        .sheet(isPresented: $showQuickSketch) {
            PencilSketchSheet(palette: store.palette, isZh: store.preferences.language == .zh) { pngData in
                Task {
                    if let att = try? await store.persistMedia(data: pngData, fileExtension: "png", type: .sketch) {
                        _ = try? await store.saveNewEntry(
                            content: store.preferences.language == .zh ? "手绘速记" : "Quick sketch note",
                            songInfo: nil,
                            media: [att],
                            mood: nil,
                            weather: nil,
                            tags: [store.preferences.language == .zh ? "涂鸦" : "sketch"],
                            isPinned: false
                        )
                    }
                }
            }
        }
        // Hardware keyboard shortcuts for iPad & Designed for iPad on Mac
        .background {
            Group {
                Button("") { openNewEntry() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("") { store.selectedTab = .journal }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { store.selectedTab = .timeline }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { store.selectedTab = .revisit }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { store.selectedTab = .ai }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { store.selectedTab = .data }
                    .keyboardShortcut("5", modifiers: .command)
                Button("") { Task { _ = await store.runBackupNow(trigger: .manual) } }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - iPhone Liquid Glass TabView Shell

    private var iPhoneTabShell: some View {
        let s = store.strings
        let p = store.palette
        return ZStack(alignment: .bottomTrailing) {
            TabView(selection: $store.selectedTab) {
                Tab(s.t("tab_journal"), systemImage: PickupTab.journal.icon, value: PickupTab.journal) {
                    NavigationStack {
                        HomeFeedView(
                            store: store,
                            onNewEntry: openNewEntry,
                            onEditEntry: openEditEntry,
                            onOpenSettings: { showSettings = true }
                        )
                    }
                }

                Tab(s.t("tab_timeline"), systemImage: PickupTab.timeline.icon, value: PickupTab.timeline) {
                    NavigationStack {
                        TimelineCalendarView(
                            store: store,
                            onEditEntry: openEditEntry,
                            onOpenSettings: { showSettings = true }
                        )
                    }
                }

                Tab(s.t("tab_revisit"), systemImage: PickupTab.revisit.icon, value: PickupTab.revisit) {
                    NavigationStack {
                        RevisitScreenView(store: store, onOpenSettings: { showSettings = true })
                    }
                }

                Tab(s.t("tab_ai"), systemImage: PickupTab.ai.icon, value: PickupTab.ai) {
                    NavigationStack {
                        AiHubView(store: store, onOpenSettings: { showSettings = true })
                    }
                }

                Tab(s.t("tab_data"), systemImage: PickupTab.data.icon, value: PickupTab.data) {
                    NavigationStack {
                        DataVaultView(store: store, onOpenSettings: { showSettings = true })
                    }
                }
            }
            .tint(p.accent)
            .pickupMinimizeTabBarOnScroll()

            // Morphing Liquid Glass Quick-Capture Pill when on Journal tab
            if store.selectedTab == .journal {
                quickCaptureGlassCluster
                    .padding(.trailing, 20)
                    .padding(.bottom, 76)
            }
        }
    }

    // MARK: - iPad Floating Liquid Glass NavigationSplitView Shell

    private var iPadSplitShell: some View {
        let p = store.palette
        let s = store.strings
        let isZh = store.preferences.language == .zh
        return NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: Binding(
                get: { store.selectedTab },
                set: { if let val = $0 { store.selectedTab = val } }
            )) {
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(p.cardSurface)
                                .frame(width: 40, height: 40)
                            AnimatedRedPenMark(color: p.redPen, lineWidth: 1.8, animate: false)
                                .frame(width: 32, height: 32)
                            Text("拾")
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .foregroundStyle(p.primaryText)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pickup")
                                .font(p.editorialFont(size: 18, weight: .bold, typography: store.preferences.typographyStyle))
                                .foregroundStyle(p.primaryText)
                            Text("\(store.entries.count) " + (isZh ? "条记忆" : "memories"))
                                .font(.caption)
                                .foregroundStyle(p.secondaryText)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section(isZh ? "空间导航" : "Spaces") {
                    ForEach(PickupTab.allCases) { tab in
                        Label(s.t("tab_\(tab.rawValue == "ai" ? "ai" : tab.rawValue)"), systemImage: store.selectedTab == tab ? tab.selectedIcon : tab.icon)
                            .tag(tab)
                            .foregroundStyle(store.selectedTab == tab ? p.accent : p.primaryText)
                    }
                }

                Section(isZh ? "快捷操作" : "Quick Actions") {
                    Button {
                        openNewEntry()
                    } label: {
                        Label(s.t("new_entry") + " (⌘N)", systemImage: "square.and.pencil")
                    }

                    Button {
                        showQuickSketch = true
                    } label: {
                        Label(s.t("add_sketch"), systemImage: "scribble.variable")
                    }

                    Button {
                        Task { _ = await store.runBackupNow(trigger: .manual) }
                    } label: {
                        Label(s.t("auto_backup_now"), systemImage: "arrow.triangle.2.circlepath.circle")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label(s.t("settings_title"), systemImage: "slider.horizontal.3")
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(PickupAmbientBackdrop(palette: p))
            .navigationTitle("Pickup")
        } detail: {
            NavigationStack {
                switch store.selectedTab {
                case .journal:
                    HomeFeedView(
                        store: store,
                        onNewEntry: openNewEntry,
                        onEditEntry: openEditEntry,
                        onOpenSettings: { showSettings = true }
                    )
                case .timeline:
                    TimelineCalendarView(
                        store: store,
                        onEditEntry: openEditEntry,
                        onOpenSettings: { showSettings = true }
                    )
                case .revisit:
                    RevisitScreenView(store: store, onOpenSettings: { showSettings = true })
                case .ai:
                    AiHubView(store: store, onOpenSettings: { showSettings = true })
                case .data:
                    DataVaultView(store: store, onOpenSettings: { showSettings = true })
                }
            }
        }
        .tint(p.accent)
    }

    // MARK: - Morphing Liquid Glass Quick-Capture Pill

    private var quickCaptureGlassCluster: some View {
        let p = store.palette
        let isZh = store.preferences.language == .zh
        return PickupGlassGroup(spacing: 12) {
            VStack(alignment: .trailing, spacing: 10) {
                if quickMenuExpanded {
                    Button {
                        quickMenuExpanded = false
                        showQuickSketch = true
                    } label: {
                        Label(isZh ? "手绘涂鸦" : "Sketch", systemImage: "scribble.variable")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(p.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .pickupGlassCapsule(interactive: true)
                    }
                    .pickupGlassIdentity("quick-sketch", in: glassNS)
                    .transition(.scale.combined(with: .opacity))

                    Button {
                        quickMenuExpanded = false
                        Task { _ = await store.runBackupNow(trigger: .manual) }
                    } label: {
                        Label(isZh ? "立即备份" : "Backup", systemImage: "externaldrive.badge.checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(p.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .pickupGlassCapsule(interactive: true)
                    }
                    .pickupGlassIdentity("quick-backup", in: glassNS)
                    .transition(.scale.combined(with: .opacity))

                    Button {
                        quickMenuExpanded = false
                        openNewEntry()
                    } label: {
                        Label(isZh ? "写日记" : "Write", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(p.tintButtonForeground)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .pickupGlassCapsule(tint: p.accent, interactive: true)
                    }
                    .pickupGlassIdentity("quick-write", in: glassNS)
                    .transition(.scale.combined(with: .opacity))
                }

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                            quickMenuExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: quickMenuExpanded ? "xmark" : "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(p.primaryText)
                            .frame(width: 44, height: 44)
                            .pickupGlassCircle(interactive: true)
                    }
                    .pickupGlassIdentity("quick-more", in: glassNS)

                    Button(action: openNewEntry) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                            Text(isZh ? "拾起一刻" : "Capture")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(p.tintButtonForeground)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .pickupGlassCapsule(tint: p.accent, interactive: true)
                    }
                    .pickupGlassIdentity("quick-primary", in: glassNS)
                }
            }
        }
    }

    private func openNewEntry() {
        editorTargetEntry = nil
        showEditor = true
    }

    private func openEditEntry(_ entry: CapsuleEntry) {
        editorTargetEntry = entry
        showEditor = true
    }
}
