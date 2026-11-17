import PickupCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct DataVaultView: View {
    @Bindable var store: AppStore
    let onOpenSettings: () -> Void

    @State private var showImporter = false
    @State private var pendingImportData: Data? = nil
    @State private var importPreview: ImportPreviewReport? = nil
    @State private var showImportConfirm = false
    @State private var importPassphrase = ""

    @State private var showVaultExportPassphrase = false
    @State private var vaultExportPassphrase = ""
    @State private var exportDoc: ExportedFileDocument? = nil
    @State private var exportFilename: String = "pickup-backup.zip"
    @State private var exportContentType: UTType = .zip
    @State private var showFileExporter = false

    @State private var showFolderPicker = false
    @State private var showFactoryResetAlert = false
    @State private var showClearAiAlert = false

    public var body: some View {
        let p = store.palette
        let s = store.strings
        let isZh = store.preferences.language == .zh

        ZStack {
            PickupAmbientBackdrop(palette: p)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header subtitle
                    Text(s.t("data_subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(p.secondaryText)

                    // 1. Storage Breakdown Ring Card
                    storageOverviewCard(palette: p, strings: s, isZh: isZh)

                    // 2. Local Import & Export Actions
                    importExportCard(palette: p, strings: s, isZh: isZh)

                    // 3. Scheduled Auto-Backup Configurator
                    autoBackupCard(palette: p, strings: s, isZh: isZh)

                    // 4. Snapshots Browser
                    snapshotsCard(palette: p, strings: s, isZh: isZh)

                    // 5. Storage Hygiene & Data Management
                    hygieneCard(palette: p, strings: s, isZh: isZh)
                }
                .padding(18)
                .padding(.bottom, 108)
            }
        }
        .navigationTitle(s.t("data_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, .json, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await handlePickedImportFile(url) }
            }
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: exportDoc,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            if case .success = result {
                store.showToast(isZh ? "已导出到本地文件：\(exportFilename)" : "Saved file: \(exportFilename)")
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            ExternalFolderPickerRepresentable { url in
                Task { await store.setExternalBackupFolder(url) }
            }
        }
        .sheet(isPresented: $showImportConfirm) {
            importPreviewSheet(palette: p, isZh: isZh)
        }
        .alert(isZh ? "设置加密导出口令" : "Set Vault Passphrase", isPresented: $showVaultExportPassphrase) {
            SecureField(isZh ? "输入加密口令" : "Passphrase", text: $vaultExportPassphrase)
            Button(s.t("cancel"), role: .cancel) { vaultExportPassphrase = "" }
            Button(isZh ? "加密导出" : "Export") {
                let pass = vaultExportPassphrase
                vaultExportPassphrase = ""
                Task { await exportVaultFile(passphrase: pass) }
            }
        } message: {
            Text(isZh ? "采用 AES-256-GCM 加密整个备份包，请牢记口令。" : "Encrypts all entries & media using AES-256-GCM.")
        }
        .confirmationDialog(isZh ? "清空所有 AI 对话历史？" : "Clear all AI history?", isPresented: $showClearAiAlert, titleVisibility: .visible) {
            Button(s.t("clear_ai_history"), role: .destructive) {
                Task {
                    try? await store.dataManagementService.clearAiHistory()
                    await store.reloadAll()
                    store.showToast(isZh ? "AI 对话记录已清空" : "AI history cleared")
                }
            }
        }
        .confirmationDialog(isZh ? "重置全部本地数据？重置前会自动创建一份安全备份快照。" : "Reset all local data? A safety backup snapshot will be created first.", isPresented: $showFactoryResetAlert, titleVisibility: .visible) {
            Button(s.t("factory_reset"), role: .destructive) {
                Task {
                    let safety = try? await store.dataManagementService.clearAllData(createSafetyBackupFirst: true)
                    await store.reloadAll()
                    store.showToast(safety != nil ? (isZh ? "已重置（已保留安全快照 \(safety!)）" : "Reset complete (safety snapshot saved)") : "Reset complete")
                }
            }
        }
    }

    // MARK: - Section 1: Storage Ring

    private func storageOverviewCard(palette p: PickupPalette, strings s: PickupStrings, isZh: Bool) -> some View {
        let bd = store.storageBreakdown
        let total = max(1, bd?.totalUsedBytes ?? 1)
        let mediaBytes = (bd?.imagesBytes ?? 0) + (bd?.videosBytes ?? 0)
        let backupsBytes = bd?.backupsBytes ?? 0
        let textBytes = (bd?.entriesBytes ?? 0) + (bd?.aiBytes ?? 0) + (bd?.draftsBytes ?? 0)

        let mediaRatio = CGFloat(mediaBytes) / CGFloat(total)
        let backupRatio = CGFloat(backupsBytes) / CGFloat(total)

        return PickupEditorialCard(palette: p, cornerRadius: 24, padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .stroke(p.elevatedSurface, lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: min(1, mediaRatio))
                            .stroke(p.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Circle()
                            .trim(from: min(1, mediaRatio), to: min(1, mediaRatio + backupRatio))
                            .stroke(p.gold, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text(formatBytes(bd?.totalUsedBytes ?? 0))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(p.primaryText)
                            Text(isZh ? "本地已用" : "Used")
                                .font(.caption2)
                                .foregroundStyle(p.tertiaryText)
                        }
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(s.t("storage_title"))
                            .font(.headline)
                            .foregroundStyle(p.primaryText)
                        metricLegendRow(color: p.primaryText, label: isZh ? "日记与 AI 文本" : "Text & AI", bytes: textBytes, p: p)
                        metricLegendRow(color: p.accent, label: isZh ? "照片 / 实况 / 视频" : "Media", bytes: mediaBytes, p: p)
                        metricLegendRow(color: p.gold, label: isZh ? "本地备份快照 (\(bd?.backupCount ?? 0))" : "Snapshots (\(bd?.backupCount ?? 0))", bytes: backupsBytes, p: p)
                        if let free = bd?.deviceFreeBytes {
                            Text((isZh ? "设备可用：" : "Device free: ") + formatBytes(free))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(p.tertiaryText)
                        }
                    }
                }
            }
        }
    }

    private func metricLegendRow(color: Color, label: String, bytes: Int64, p: PickupPalette) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(p.secondaryText)
            Spacer()
            Text(formatBytes(bytes)).font(.caption.monospacedDigit()).foregroundStyle(p.primaryText)
        }
    }

    // MARK: - Section 2: Import & Export

    private func importExportCard(palette p: PickupPalette, strings s: PickupStrings, isZh: Bool) -> some View {
        PickupEditorialCard(palette: p, cornerRadius: 24, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(s.t("import_export_title"))
                    .font(.headline)
                    .foregroundStyle(p.primaryText)

                actionRow(icon: "arrow.up.doc.fill", title: s.t("export_zip"), subtitle: s.t("export_zip_desc"), tint: p.accent, p: p) {
                    Task { await exportPortableZipFile() }
                }

                actionRow(icon: "lock.doc.fill", title: s.t("export_vault"), subtitle: s.t("export_vault_desc"), tint: p.gold, p: p) {
                    showVaultExportPassphrase = true
                }

                actionRow(icon: "doc.richtext.fill", title: s.t("export_md"), subtitle: s.t("export_md_desc"), tint: p.secondaryText, p: p) {
                    Task { await exportMarkdownFile() }
                }

                Divider().overlay(p.hairline)

                actionRow(icon: "square.and.arrow.down.fill", title: s.t("import_backup"), subtitle: s.t("import_backup_desc"), tint: p.redPen, p: p) {
                    showImporter = true
                }
            }
        }
    }

    private func actionRow(icon: String, title: String, subtitle: String, tint: Color, p: PickupPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(p.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(p.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(p.tertiaryText)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Section 3: Scheduled Auto-Backup

    private func autoBackupCard(palette p: PickupPalette, strings s: PickupStrings, isZh: Bool) -> some View {
        let ab = store.preferences.autoBackup
        let timeBinding = Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: ab.preferredHour, minute: ab.preferredMinute, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                Task {
                    await store.updatePreferences {
                        $0.autoBackup.preferredHour = comps.hour ?? 22
                        $0.autoBackup.preferredMinute = comps.minute ?? 30
                    }
                }
            }
        )

        return PickupEditorialCard(palette: p, cornerRadius: 24, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(s.t("auto_backup_title"))
                        .font(.headline)
                        .foregroundStyle(p.primaryText)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { ab.isEnabled },
                        set: { val in Task { await store.updatePreferences { $0.autoBackup.isEnabled = val } } }
                    ))
                    .labelsHidden()
                    .tint(p.accent)
                }

                // Frequency picker
                HStack {
                    Text(s.t("auto_backup_freq"))
                        .font(.subheadline)
                        .foregroundStyle(p.secondaryText)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { ab.frequency },
                        set: { val in Task { await store.updatePreferences { $0.autoBackup.frequency = val } } }
                    )) {
                        Text(isZh ? "每 6 小时" : "Every 6h").tag(BackupFrequency.every6Hours)
                        Text(isZh ? "每天定时" : "Daily").tag(BackupFrequency.daily)
                        Text(isZh ? "每周" : "Weekly").tag(BackupFrequency.weekly)
                        Text(isZh ? "每次变更" : "On Edit").tag(BackupFrequency.onEntryChange)
                        Text(isZh ? "退入后台" : "On Background").tag(BackupFrequency.onAppBackground)
                        Text(isZh ? "仅手动" : "Manual Only").tag(BackupFrequency.manualOnly)
                    }
                    .tint(p.accent)
                }

                if ab.frequency == .daily {
                    DatePicker(s.t("auto_backup_time"), selection: timeBinding, displayedComponents: .hourAndMinute)
                        .font(.subheadline)
                        .foregroundStyle(p.secondaryText)
                }

                HStack {
                    Text(s.t("auto_backup_retention"))
                        .font(.subheadline)
                        .foregroundStyle(p.secondaryText)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { ab.retentionCount },
                        set: { val in Task { await store.updatePreferences { $0.autoBackup.retentionCount = val } } }
                    )) {
                        Text("3").tag(3)
                        Text("7").tag(7)
                        Text("14").tag(14)
                        Text("30").tag(30)
                        Text(isZh ? "全部保留" : "Keep All").tag(0)
                    }
                    .tint(p.accent)
                }

                Toggle(s.t("auto_backup_include_media"), isOn: Binding(
                    get: { ab.includeMedia },
                    set: { val in Task { await store.updatePreferences { $0.autoBackup.includeMedia = val } } }
                ))
                .font(.subheadline)
                .foregroundStyle(p.secondaryText)
                .tint(p.accent)

                Divider().overlay(p.hairline)

                // External mirror directory (protects data if free 7-day sideload expires!)
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.t("auto_backup_external"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(p.secondaryText)

                    HStack {
                        Image(systemName: ab.externalFolderDisplayName == nil ? "folder.badge.plus" : "folder.fill.badge.checkmark")
                            .foregroundStyle(ab.externalFolderDisplayName == nil ? p.tertiaryText : p.gold)
                        Text(ab.externalFolderDisplayName ?? (isZh ? "未绑定外部目录（强烈建议绑定到「文件」或 NAS 防止免费签名过期丢失）" : "Not linked (recommended for zero-fee sideload safety)"))
                            .font(.caption)
                            .foregroundStyle(p.secondaryText)
                        Spacer()
                        Button(s.t("auto_backup_pick_folder")) {
                            showFolderPicker = true
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(p.accent)
                    }
                }

                Button {
                    Task { _ = await store.runBackupNow(trigger: .manual) }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(s.t("auto_backup_now"))
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(p.tintButtonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .pickupGlassCapsule(tint: p.accent, interactive: true)
                }

                if let last = ab.lastSuccessAt {
                    Text((isZh ? "上次成功备份：" : "Last backup: ") + last.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(p.tertiaryText)
                }
            }
        }
    }

    // MARK: - Section 4: Snapshots Browser

    private func snapshotsCard(palette p: PickupPalette, strings s: PickupStrings, isZh: Bool) -> some View {
        PickupEditorialCard(palette: p, cornerRadius: 24, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(s.t("snapshots_title"))
                        .font(.headline)
                        .foregroundStyle(p.primaryText)
                    Spacer()
                    Text("\(store.snapshots.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(p.tertiaryText)
                }

                if store.snapshots.isEmpty {
                    Text(isZh ? "暂无本地快照，点击上方「立即执行一次备份」创建第一份。" : "No snapshots yet. Tap Back Up Now above.")
                        .font(.subheadline)
                        .foregroundStyle(p.tertiaryText)
                } else {
                    ForEach(store.snapshots) { snap in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: snap.metadata.isPinned ? "pin.fill" : "archivebox.fill")
                                    .foregroundStyle(snap.metadata.isPinned ? p.gold : p.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snap.metadata.fileName)
                                        .font(.caption.weight(.semibold).monospaced())
                                        .foregroundStyle(p.primaryText)
                                        .lineLimit(1)
                                    Text("\(snap.metadata.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(formatBytes(snap.metadata.byteSize)) · \(snap.metadata.entryCount) " + (isZh ? "条" : "entries"))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(p.secondaryText)
                                }
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                ShareLink(item: snap.fileURL) {
                                    Label(isZh ? "导出" : "Share", systemImage: "square.and.arrow.up")
                                        .font(.caption2.weight(.semibold))
                                }
                                .tint(p.accent)

                                Button {
                                    Task {
                                        _ = try? await store.autoBackupEngine.togglePin(snapshotId: snap.id)
                                        await store.reloadAll()
                                    }
                                } label: {
                                    Label(snap.metadata.isPinned ? (isZh ? "取消置顶" : "Unpin") : (isZh ? "锁定防删" : "Pin"), systemImage: "pin")
                                        .font(.caption2.weight(.semibold))
                                }
                                .tint(p.gold)

                                Button {
                                    Task {
                                        if let report = try? await store.autoBackupEngine.restoreSnapshot(id: snap.id, mode: .merge) {
                                            await store.reloadAll()
                                            store.showToast(isZh ? "已合并恢复 \(report.importedEntries) 条记录" : "Merged \(report.importedEntries) entries")
                                        }
                                    }
                                } label: {
                                    Label(isZh ? "合并恢复" : "Merge", systemImage: "arrow.counterclockwise")
                                        .font(.caption2.weight(.semibold))
                                }
                                .tint(p.primaryText)

                                Spacer()

                                Button(role: .destructive) {
                                    Task {
                                        _ = try? await store.autoBackupEngine.deleteSnapshot(id: snap.id)
                                        await store.reloadAll()
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(p.redPen)
                                }
                            }
                        }
                        .padding(12)
                        .background(p.elevatedSurface, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
    }

    // MARK: - Section 5: Storage Hygiene

    private func hygieneCard(palette p: PickupPalette, strings s: PickupStrings, isZh: Bool) -> some View {
        let orphanCount = store.orphanScan?.orphanMediaIds.count ?? 0
        let orphanBytes = store.orphanScan?.orphanByteSize ?? 0
        let missingCount = store.orphanScan?.missingMediaRefs.count ?? 0

        return PickupEditorialCard(palette: p, cornerRadius: 24, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(s.t("hygiene_title"))
                    .font(.headline)
                    .foregroundStyle(p.primaryText)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isZh ? "孤儿冗余媒体：\(orphanCount) 个 (\(formatBytes(orphanBytes)))" : "Orphan media: \(orphanCount) (\(formatBytes(orphanBytes)))")
                            .font(.subheadline)
                            .foregroundStyle(p.primaryText)
                        Text(isZh ? "缺失媒体引用：\(missingCount) 处" : "Missing media references: \(missingCount)")
                            .font(.caption)
                            .foregroundStyle(p.secondaryText)
                    }
                    Spacer()
                    if orphanCount > 0 {
                        Button(s.t("purge_orphans")) {
                            Task {
                                let res = try? await store.dataManagementService.purgeOrphanMedia()
                                await store.reloadAll()
                                if let res {
                                    store.showToast(isZh ? "已清理 \(res.deletedCount) 个冗余文件，释放 \(formatBytes(res.freedBytes))" : "Purged \(res.deletedCount) files")
                                }
                            }
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(p.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .pickupGlassCapsule()
                    } else {
                        Label(isZh ? "很干净" : "Clean", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(p.accent)
                    }
                }

                if let heavy = store.orphanScan?.heavyMediaItems, !heavy.isEmpty {
                    Divider().overlay(p.hairline)
                    Text(s.t("heavy_media"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(p.secondaryText)
                    ForEach(heavy.prefix(4)) { item in
                        HStack {
                            Image(systemName: item.isVideo ? "video.fill" : "photo.fill")
                                .foregroundStyle(p.secondaryText)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.entryPreview)
                                    .font(.caption)
                                    .foregroundStyle(p.primaryText)
                                    .lineLimit(1)
                                Text(formatBytes(item.byteSize))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(p.tertiaryText)
                            }
                            Spacer()
                        }
                    }
                }

                Divider().overlay(p.hairline)

                HStack(spacing: 12) {
                    Button {
                        showClearAiAlert = true
                    } label: {
                        Text(s.t("clear_ai_history"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(p.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(p.elevatedSurface, in: Capsule())
                    }

                    Button {
                        showFactoryResetAlert = true
                    } label: {
                        Text(s.t("factory_reset"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(p.redPen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(p.redPen.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Import / Export Helpers

    private func exportPortableZipFile() async {
        do {
            let res = try await store.backupService.exportPortableZip(includeMedia: true)
            exportDoc = ExportedFileDocument(data: res.data)
            exportFilename = "pickup-portable-\(Self.dateStamp()).zip"
            exportContentType = .zip
            showFileExporter = true
        } catch {
            store.showToast(error.localizedDescription)
        }
    }

    private func exportVaultFile(passphrase: String) async {
        do {
            let res = try await store.backupService.exportEncryptedVault(passphrase: passphrase, includeMedia: true)
            exportDoc = ExportedFileDocument(data: res.data)
            exportFilename = "pickup-vault-\(Self.dateStamp()).pickupvault"
            exportContentType = .data
            showFileExporter = true
        } catch {
            store.showToast(error.localizedDescription)
        }
    }

    private func exportMarkdownFile() async {
        do {
            let data = try await store.backupService.exportMarkdownAnthology(includeMedia: true)
            exportDoc = ExportedFileDocument(data: data)
            exportFilename = "pickup-anthology-\(Self.dateStamp()).zip"
            exportContentType = .zip
            showFileExporter = true
        } catch {
            store.showToast(error.localizedDescription)
        }
    }

    private func handlePickedImportFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pendingImportData = data
            if VaultCrypto.looksLikeEncryptedVault(data) {
                importPreview = ImportPreviewReport(format: .encryptedVault, entryCount: 0, aiEntryCount: 0, mediaCount: 0, missingMediaCount: 0, conflictCount: 0, hasIOSExtensions: true, exportedAt: nil)
            } else {
                importPreview = try await store.backupService.inspectInput(data: data)
            }
            showImportConfirm = true
        } catch {
            store.showToast(error.localizedDescription)
        }
    }

    private func importPreviewSheet(palette p: PickupPalette, isZh: Bool) -> some View {
        NavigationStack {
            ZStack {
                PickupAmbientBackdrop(palette: p)
                VStack(alignment: .leading, spacing: 16) {
                    if let preview = importPreview {
                        PickupEditorialCard(palette: p, cornerRadius: 20, padding: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(isZh ? "检测到格式" : "Format"): \(preview.format.rawValue)")
                                    .font(.headline)
                                    .foregroundStyle(p.accent)
                                if preview.format == .encryptedVault {
                                    SecureField(isZh ? "输入保险箱口令" : "Vault passphrase", text: $importPassphrase)
                                        .padding(12)
                                        .background(p.elevatedSurface, in: RoundedRectangle(cornerRadius: 12))
                                } else {
                                    Text(isZh ? "日记条目：\(preview.entryCount) · AI 记录：\(preview.aiEntryCount) · 媒体：\(preview.mediaCount) · 重复冲突：\(preview.conflictCount)" : "Entries: \(preview.entryCount) · AI: \(preview.aiEntryCount) · Media: \(preview.mediaCount) · Conflicts: \(preview.conflictCount)")
                                        .font(.subheadline)
                                        .foregroundStyle(p.primaryText)
                                }
                            }
                        }

                        Button {
                            runImport(mode: .merge)
                        } label: {
                            Text(store.strings.t("import_mode_merge"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(p.tintButtonForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .pickupGlassCapsule(tint: p.accent, interactive: true)
                        }

                        Button {
                            runImport(mode: .replace)
                        } label: {
                            Text(store.strings.t("import_mode_replace"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(p.redPen)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .pickupGlassCapsule(interactive: true)
                        }
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle(store.strings.t("import_backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.strings.t("cancel")) { showImportConfirm = false }
                }
            }
        }
    }

    private func runImport(mode: ImportMode) {
        guard let data = pendingImportData else { return }
        let pass = importPassphrase
        let isZh = store.preferences.language == .zh
        Task {
            do {
                let report = try await store.backupService.importData(data, mode: mode, passphrase: pass.isEmpty ? nil : pass)
                importPassphrase = ""
                pendingImportData = nil
                showImportConfirm = false
                await store.reloadAll()
                store.showToast(isZh ? "导入成功：新增 \(report.importedEntries) 条记忆，媒体 \(report.importedMedia) 个" : "Imported \(report.importedEntries) entries, \(report.importedMedia) media")
            } catch {
                store.showToast(error.localizedDescription)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func dateStamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        return df.string(from: Date())
    }
}

public struct ExportedFileDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.zip, .data, .json] }
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct ExternalFolderPickerRepresentable: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ExternalFolderPickerRepresentable
        init(parent: ExternalFolderPickerRepresentable) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onPick(url)
            }
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}
