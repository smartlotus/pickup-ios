import PickupCore
import SwiftUI

public struct AiHubView: View {
    @Bindable var store: AppStore
    let onOpenSettings: () -> Void

    @State private var question: String = ""
    @State private var scope: AiRecallScope = .intelligent
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()
    @State private var pendingDisclosure: AiDisclosurePreview? = nil
    @State private var pendingType: AiEntryType = .recall
    @State private var showProviderSheet = false
    @State private var isSending = false
    @State private var runningTask: Task<Void, Never>? = nil

    public var body: some View {
        let p = store.palette
        let s = store.strings
        let isZh = store.preferences.language == .zh

        ZStack {
            PickupAmbientBackdrop(palette: p)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Privacy banner
                    PickupEditorialCard(palette: p, cornerRadius: 20, padding: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.shield.fill")
                                .font(.title2)
                                .foregroundStyle(p.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.t("ai_subtitle"))
                                    .font(.caption)
                                    .foregroundStyle(p.secondaryText)
                                Text("\(store.aiSettings.provider.displayName) · \(store.aiSettings.model)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(p.tertiaryText)
                            }
                            Spacer()
                            Button(isZh ? "配置" : "Setup") {
                                showProviderSheet = true
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(p.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .pickupGlassCapsule()
                        }
                    }

                    // Scope Picker
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: $scope) {
                            Text(s.t("ai_scope_smart")).tag(AiRecallScope.intelligent)
                            Text(s.t("ai_scope_all")).tag(AiRecallScope.all)
                            Text(s.t("ai_scope_custom")).tag(AiRecallScope.custom)
                        }
                        .pickerStyle(.segmented)

                        if scope == .custom {
                            HStack {
                                DatePicker(isZh ? "开始" : "From", selection: $customStart, displayedComponents: .date)
                                DatePicker(isZh ? "结束" : "To", selection: $customEnd, displayedComponents: .date)
                            }
                            .font(.caption)
                            .foregroundStyle(p.secondaryText)
                        }
                    }

                    // Prompt Composer
                    PickupEditorialCard(palette: p, cornerRadius: 22, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField(s.t("ai_ask_placeholder"), text: $question, axis: .vertical)
                                .lineLimit(2...5)
                                .font(.body)
                                .foregroundStyle(p.primaryText)

                            HStack(spacing: 10) {
                                Button {
                                    prepareDisclosure(type: .recall)
                                } label: {
                                    Label(s.t("ai_ask_button"), systemImage: "sparkles")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(p.tintButtonForeground)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .pickupGlassCapsule(tint: p.accent, interactive: true)
                                }
                                .disabled(isSending || store.entries.isEmpty)

                                Button {
                                    prepareDisclosure(type: .summary)
                                } label: {
                                    Label(s.t("ai_summary_button"), systemImage: "doc.text.magnifyingglass")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(p.primaryText)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .pickupGlassCapsule(interactive: true)
                                }
                                .disabled(isSending || store.entries.isEmpty)

                                if isSending {
                                    Spacer()
                                    Button(role: .destructive) {
                                        runningTask?.cancel()
                                        isSending = false
                                    } label: {
                                        Text(s.t("cancel"))
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(p.redPen)
                                    }
                                }
                            }
                        }
                    }

                    // History
                    VStack(alignment: .leading, spacing: 12) {
                        Text(s.t("ai_history"))
                            .font(.headline)
                            .foregroundStyle(p.primaryText)

                        if store.aiEntries.isEmpty {
                            Text(isZh ? "尚无回忆对话记录。" : "No AI reflections saved yet.")
                                .font(.subheadline)
                                .foregroundStyle(p.tertiaryText)
                        } else {
                            ForEach(store.aiEntries) { ai in
                                PickupEditorialCard(palette: p, cornerRadius: 20, padding: 16) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(ai.type == .summary ? (isZh ? "总结" : "SUMMARY") : (isZh ? "问答" : "RECALL"))
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(p.accent)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(p.accent.opacity(0.15), in: Capsule())
                                            Text(ai.timestamp.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(p.tertiaryText)
                                            Spacer()
                                            Button {
                                                Task {
                                                    _ = try? await store.repository.deleteAiEntry(id: ai.id)
                                                    await store.reloadAll()
                                                }
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.caption)
                                                    .foregroundStyle(p.tertiaryText)
                                            }
                                        }
                                        Text(ai.question)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(p.primaryText)
                                        Text(ai.answer)
                                            .font(.subheadline)
                                            .lineSpacing(5)
                                            .foregroundStyle(p.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(18)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle(s.t("tab_ai"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(item: Binding(
            get: { pendingDisclosure.map { DisclosureBox(preview: $0) } },
            set: { if $0 == nil { pendingDisclosure = nil } }
        )) { box in
            AiDisclosureConfirmSheet(
                store: store,
                preview: box.preview,
                onConfirm: {
                    let preview = box.preview
                    pendingDisclosure = nil
                    sendConfirmed(preview: preview, type: pendingType)
                }
            )
        }
        .sheet(isPresented: $showProviderSheet) {
            AiProviderSettingsSheet(store: store)
        }
    }

    private func prepareDisclosure(type: AiEntryType) {
        pendingType = type
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveQ = q.isEmpty
            ? (store.preferences.language == .zh ? "总结这段时间的日常脉络与情绪变化" : "Summarize the key threads and moods across these entries")
            : q
        pendingDisclosure = AiHubService.buildDisclosure(
            question: effectiveQ,
            scope: scope,
            customStart: customStart,
            customEnd: customEnd,
            entries: store.entries,
            providerName: store.aiSettings.provider.displayName
        )
    }

    private func sendConfirmed(preview: AiDisclosurePreview, type: AiEntryType) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = q.isEmpty ? (store.preferences.language == .zh ? "时段总结" : "Period Summary") : q
        let prompt = """
        Question / Request: \(title)

        Disclosed Journal Entries (\(preview.recordCount) records, text only):
        \(preview.previewText)
        """
        isSending = true
        runningTask = Task {
            defer { isSending = false }
            do {
                _ = try await store.aiHubService.executeRequest(
                    settings: store.aiSettings,
                    prompt: prompt,
                    disclosure: preview,
                    type: type,
                    questionTitle: title
                )
                question = ""
                await store.reloadAll()
            } catch {
                store.showToast(error.localizedDescription)
            }
        }
    }
}

private struct DisclosureBox: Identifiable {
    let id = UUID()
    let preview: AiDisclosurePreview
}

private struct AiDisclosureConfirmSheet: View {
    let store: AppStore
    let preview: AiDisclosurePreview
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let p = store.palette
        let isZh = store.preferences.language == .zh
        NavigationStack {
            ZStack {
                PickupAmbientBackdrop(palette: p)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        PickupEditorialCard(palette: p, cornerRadius: 18, padding: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("\(isZh ? "目标服务" : "Provider"): \(preview.providerName)", systemImage: "server.rack")
                                Label("\(isZh ? "包含记录数" : "Entries included"): \(preview.recordCount)", systemImage: "doc.text")
                                Label("\(isZh ? "总字符数" : "Characters"): \(preview.characterCount)", systemImage: "character.cursor.ibeam")
                                Label(isZh ? "包含照片/视频字节：否 (0 bytes)" : "Media bytes sent: NO (0 bytes)", systemImage: "photo.badge.exclamationmark")
                                    .foregroundStyle(p.accent)
                            }
                            .font(.subheadline)
                            .foregroundStyle(p.primaryText)
                        }

                        Text(isZh ? "以下文本将被发送到你配置的 AI 端点：" : "Exact text payload to be transmitted:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(p.secondaryText)

                        Text(preview.previewText.isEmpty ? "—" : preview.previewText)
                            .font(.caption.monospaced())
                            .foregroundStyle(p.primaryText)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(p.cardSurface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(18)
                }
            }
            .navigationTitle(store.strings.t("ai_disclosure_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.strings.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.strings.t("ai_disclosure_confirm")) {
                        onConfirm()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }
}

private struct AiProviderSettingsSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AiSettings = AiSettings()
    @State private var testResult: String? = nil
    @State private var testing = false

    var body: some View {
        let p = store.palette
        let isZh = store.preferences.language == .zh
        NavigationStack {
            Form {
                Section(isZh ? "AI 服务商" : "Provider") {
                    Picker(isZh ? "服务" : "Provider", selection: $draft.provider) {
                        ForEach(AiProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .onChange(of: draft.provider) { _, next in
                        draft.model = next.defaultModel
                    }

                    TextField(isZh ? "模型名称" : "Model", text: $draft.model)
                    if draft.provider == .custom {
                        TextField("https://...", text: $draft.customEndpointURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SecureField("API Key (Stored locally)", text: $draft.apiKey)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button {
                        testing = true
                        testResult = nil
                        Task {
                            defer { testing = false }
                            do {
                                let res = try await store.aiHubService.testConnection(settings: draft)
                                testResult = "OK: \(res)"
                            } catch {
                                testResult = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack {
                            Text(isZh ? "测试连接" : "Test Connection")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("OK") ? p.accent : p.redPen)
                    }
                }
            }
            .navigationTitle(store.strings.t("ai_settings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.strings.t("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.strings.t("save")) {
                        Task {
                            try? await store.aiHubService.saveSettings(draft)
                            await store.reloadAll()
                            dismiss()
                        }
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            draft = store.aiSettings
        }
    }
}
