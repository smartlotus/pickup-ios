import Photos
import PhotosUI
import PickupCore
import SwiftUI
import UniformTypeIdentifiers

public struct RichEditorView: View {
    @Bindable var store: AppStore
    let existingEntry: CapsuleEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    @State private var songInfo: String = ""
    @State private var mood: String = ""
    @State private var weather: String = ""
    @State private var tagsText: String = ""
    @State private var isPinned: Bool = false
    @State private var media: [MediaAttachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var reflectionText: String = ""
    @State private var showSketch = false
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    @State private var errorMsg: String? = nil
    @State private var draftSaveTask: Task<Void, Never>? = nil

    private var promptsZh: [String] {
        ["今天发生了什么？", "我现在的心情是…", "今天感谢…", "明天想要…"]
    }
    private var promptsEn: [String] {
        ["What happened today?", "Right now I feel…", "Grateful for…", "Tomorrow I hope…"]
    }
    private var moodChips: [String] {
        store.preferences.language == .zh
            ? ["平静", "松弛", "微光", "怀旧", "疲惫", "热忱"]
            : ["Calm", "Cozy", "Hopeful", "Nostalgic", "Tired", "Bright"]
    }

    public init(store: AppStore, existingEntry: CapsuleEntry? = nil) {
        self.store = store
        self.existingEntry = existingEntry
    }

    public var body: some View {
        let p = store.palette
        let s = store.strings
        let isZh = store.preferences.language == .zh
        NavigationStack {
            ZStack {
                PickupAmbientBackdrop(palette: p)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Prompt chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(isZh ? promptsZh : promptsEn, id: \.self) { prompt in
                                    Button {
                                        if !content.isEmpty && !content.hasSuffix("\n") {
                                            content += "\n"
                                        }
                                        content += prompt + " "
                                    } label: {
                                        Text(prompt)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(p.secondaryText)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(p.cardSurface, in: Capsule())
                                            .overlay(Capsule().strokeBorder(p.hairline))
                                    }
                                }
                            }
                        }

                        // Text editor
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $content)
                                .scrollContentBackground(.hidden)
                                .font(p.bodyFont(size: 17))
                                .foregroundStyle(p.primaryText)
                                .frame(minHeight: 190)
                                .padding(12)
                                .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(p.hairline))

                            HStack {
                                Text(existingEntry == nil ? s.t("draft_saved") : existingEntry!.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(p.tertiaryText)
                                Spacer()
                                Text("\(content.count) " + (isZh ? "字" : "chars"))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(p.tertiaryText)
                            }
                        }

                        // Song + Mood + Weather + Tags
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "music.note")
                                    .foregroundStyle(p.accent)
                                TextField(s.t("song_hint"), text: $songInfo)
                                    .font(.subheadline)
                            }
                            .padding(12)
                            .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 14))

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    Text(s.t("mood_label"))
                                        .font(.caption)
                                        .foregroundStyle(p.secondaryText)
                                    ForEach(moodChips, id: \.self) { chip in
                                        Button {
                                            mood = (mood == chip) ? "" : chip
                                        } label: {
                                            Text(chip)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(mood == chip ? p.tintButtonForeground : p.secondaryText)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(mood == chip ? p.accent : p.cardSurface, in: Capsule())
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 10) {
                                TextField(s.t("weather_label"), text: $weather)
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 14))
                                TextField(s.t("tags_hint"), text: $tagsText)
                                    .font(.subheadline)
                                    .padding(12)
                                    .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }

                        // Media Picker & Sketch
                        HStack(spacing: 12) {
                            PhotosPicker(
                                selection: $pickerItems,
                                maxSelectionCount: 9,
                                matching: .any(of: [.images, .videos, .livePhotos])
                            ) {
                                PickedMediaButtonLabel(
                                    title: s.t("add_media"),
                                    systemImage: "photo.on.rectangle.angled",
                                    foreground: p.primaryText
                                )
                            }

                            Button {
                                showSketch = true
                            } label: {
                                PickedMediaButtonLabel(
                                    title: s.t("add_sketch"),
                                    systemImage: "scribble.variable",
                                    foreground: p.primaryText
                                )
                            }
                        }

                        if !media.isEmpty {
                            MediaAttachmentStrip(store: store, attachments: media, onTap: { _ in }, onRemove: { att in
                                media.removeAll { $0.id == att.id }
                            })
                        }

                        // Reflections when editing
                        if let existingEntry {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(s.t("reflections_title"))
                                    .font(.headline)
                                    .foregroundStyle(p.primaryText)
                                ForEach(existingEntry.comments) { c in
                                    Text("“\(c.text)” — \(c.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.subheadline)
                                        .foregroundStyle(p.secondaryText)
                                }
                                HStack {
                                    TextField(s.t("reflection_hint"), text: $reflectionText)
                                        .padding(10)
                                        .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 12))
                                    Button(s.t("send_reflection")) {
                                        let txt = reflectionText
                                        reflectionText = ""
                                        Task {
                                            await store.addReflection(to: existingEntry, text: txt)
                                        }
                                    }
                                    .disabled(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                            .padding(.top, 8)
                        }

                        if let errorMsg {
                            Text(errorMsg)
                                .font(.footnote)
                                .foregroundStyle(p.redPen)
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle(existingEntry == nil ? s.t("new_entry") : s.t("edit_entry"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(s.t("cancel")) { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isPinned.toggle()
                    } label: {
                        Image(systemName: isPinned ? "star.fill" : "star")
                            .foregroundStyle(isPinned ? p.accent : p.secondaryText)
                    }
                    if existingEntry != nil {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(p.redPen)
                        }
                    }
                    Button {
                        Task { await saveEntry() }
                    } label: {
                        Text(s.t("save"))
                            .fontWeight(.bold)
                    }
                    .disabled(isSaving)
                }
            }
        }
        .onAppear {
            if let existingEntry {
                content = existingEntry.content
                songInfo = existingEntry.songInfo ?? ""
                mood = existingEntry.mood ?? ""
                weather = existingEntry.weather ?? ""
                tagsText = existingEntry.tags.joined(separator: ", ")
                isPinned = existingEntry.isPinned
                media = existingEntry.media
            } else {
                Task { await restoreDraft() }
            }
        }
        .onChange(of: content) { _, _ in scheduleDraftSave() }
        .onChange(of: songInfo) { _, _ in scheduleDraftSave() }
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await importPickedItems(newItems) }
        }
        .sheet(isPresented: $showSketch) {
            PencilSketchSheet(palette: p, isZh: isZh) { pngData in
                Task {
                    if let att = try? await store.persistMedia(data: pngData, fileExtension: "png", type: .sketch) {
                        media.append(att)
                    }
                }
            }
        }
        .confirmationDialog(isZh ? "删除这条日记？" : "Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(s.t("delete"), role: .destructive) {
                if let existingEntry {
                    Task {
                        await store.deleteEntry(existingEntry)
                        dismiss()
                    }
                }
            }
        }
    }

    private func restoreDraft() async {
        guard let draft = try? await store.repository.loadDraft(), !draft.isEffectivelyEmpty else {
            return
        }
        content = draft.content
        songInfo = draft.songInfo
        mood = draft.mood ?? ""
        weather = draft.weather ?? ""
        tagsText = draft.tags.joined(separator: ", ")
        media = draft.media
    }

    private func scheduleDraftSave() {
        guard existingEntry == nil else { return }
        draftSaveTask?.cancel()
        let snapshot = EditorDraft(
            content: content,
            songInfo: songInfo,
            mood: mood.isEmpty ? nil : mood,
            weather: weather.isEmpty ? nil : weather,
            tags: parsedTags,
            media: media
        )
        draftSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            try? await store.repository.saveDraft(snapshot)
        }
    }

    private var parsedTags: [String] {
        tagsText
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func saveEntry() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let existingEntry {
                _ = try await store.updateExistingEntry(
                    original: existingEntry,
                    content: content,
                    songInfo: songInfo,
                    media: media,
                    mood: mood,
                    weather: weather,
                    tags: parsedTags,
                    isPinned: isPinned
                )
            } else {
                _ = try await store.saveNewEntry(
                    content: content,
                    songInfo: songInfo,
                    media: media,
                    mood: mood,
                    weather: weather,
                    tags: parsedTags,
                    isPinned: isPinned
                )
            }
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func importPickedItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
                if let movie = try? await item.loadTransferable(type: PickedMovieData.self),
                   let att = try? await store.persistMedia(data: movie.data, fileExtension: movie.ext, type: .video) {
                    media.append(att)
                }
            } else if let data = try? await item.loadTransferable(type: Data.self) {
                let isLive = item.supportedContentTypes.contains(where: { $0.conforms(to: .livePhoto) })
                if let att = try? await store.persistMedia(
                    data: data,
                    fileExtension: "jpg",
                    type: isLive ? .motionPhoto : .image
                ) {
                    media.append(att)
                }
            }
        }
        pickerItems = []
        scheduleDraftSave()
    }
}

private struct PickedMovieData: Transferable, Sendable {
    let data: Data
    let ext: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let data = try Data(contentsOf: received.file)
            let ext = received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension.lowercased()
            return PickedMovieData(data: data, ext: ext)
        }
    }
}

private struct PickedMediaButtonLabel: View {
    let title: String
    let systemImage: String
    let foreground: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .pickupGlassCapsule(interactive: true)
    }
}
