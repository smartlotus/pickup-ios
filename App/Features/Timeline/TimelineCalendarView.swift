import PickupCore
import SwiftUI

public struct TimelineCalendarView: View {
    @Bindable var store: AppStore
    let onEditEntry: (CapsuleEntry) -> Void
    let onOpenSettings: () -> Void

    @State private var displayMonth: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var inspectedMedia: MediaAttachment? = nil
    @State private var inspectedEntryMedia: [MediaAttachment] = []

    private let calendar = Calendar.current

    public var body: some View {
        let p = store.palette
        let s = store.strings
        let isZh = store.preferences.language == .zh
        let counts = JournalService.dayCounts(for: store.entries, inMonthOf: displayMonth, calendar: calendar)
        let selectedEntries = JournalService.entriesOnDay(selectedDate, from: store.entries, calendar: calendar)
        let onThisDay = store.onThisDayEntries

        ZStack {
            PickupAmbientBackdrop(palette: p)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header + Streak badge
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.t("timeline_subtitle"))
                                .font(.caption)
                                .foregroundStyle(p.secondaryText)
                            Text(monthTitle(displayMonth, isZh: isZh))
                                .font(p.editorialFont(size: 26, weight: .bold, typography: store.preferences.typographyStyle))
                                .foregroundStyle(p.primaryText)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(p.redPen)
                            Text("\(store.streakDays) \(s.t("days_unit"))")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(p.primaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .pickupGlassCapsule(interactive: false)
                    }

                    // Month switcher + Grid
                    PickupEditorialCard(palette: p, cornerRadius: 24, padding: 18) {
                        VStack(spacing: 16) {
                            HStack {
                                Button {
                                    shiftMonth(by: -1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .frame(width: 34, height: 34)
                                        .pickupGlassCircle()
                                }
                                Spacer()
                                Text(isZh ? "红笔圈记有回忆的日子" : "Red ink marks recorded days")
                                    .font(.caption)
                                    .foregroundStyle(p.tertiaryText)
                                Spacer()
                                Button {
                                    shiftMonth(by: 1)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .frame(width: 34, height: 34)
                                        .pickupGlassCircle()
                                }
                            }

                            let weekdays = isZh ? ["一", "二", "三", "四", "五", "六", "日"] : ["M", "T", "W", "T", "F", "S", "S"]
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                                ForEach(weekdays, id: \.self) { wd in
                                    Text(wd)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(p.tertiaryText)
                                }

                                let days = monthCells(for: displayMonth)
                                ForEach(Array(days.enumerated()), id: \.offset) { _, dayCell in
                                    if let day = dayCell {
                                        let hasEntries = (counts[day] ?? 0) > 0
                                        let cellDate = dateFor(day: day, in: displayMonth)
                                        let isSelected = calendar.isDate(cellDate, inSameDayAs: selectedDate)
                                        Button {
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedDate = cellDate
                                            }
                                        } label: {
                                            ZStack {
                                                if isSelected {
                                                    Circle()
                                                        .fill(p.accent.opacity(0.24))
                                                        .frame(width: 38, height: 38)
                                                }
                                                if hasEntries {
                                                    AnimatedRedPenMark(color: p.redPen, lineWidth: 2.0, animate: true)
                                                        .frame(width: 36, height: 36)
                                                }
                                                Text("\(day)")
                                                    .font(.subheadline.monospacedDigit().weight(hasEntries || isSelected ? .bold : .regular))
                                                    .foregroundStyle(hasEntries || isSelected ? p.primaryText : p.secondaryText)
                                            }
                                            .frame(height: 40)
                                        }
                                    } else {
                                        Color.clear.frame(height: 40)
                                    }
                                }
                            }
                        }
                    }

                    // On This Day ("记忆回响")
                    if !onThisDay.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(p.highlight)
                                Text(s.t("on_this_day"))
                                    .font(.headline)
                                    .foregroundStyle(p.primaryText)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(onThisDay) { echo in
                                        PickupEditorialCard(palette: p, cornerRadius: 18, padding: 14, isPinned: true) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(echo.timestamp.formatted(date: .long, time: .omitted))
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(p.highlight)
                                                Text(echo.content)
                                                    .font(.subheadline)
                                                    .foregroundStyle(p.primaryText)
                                                    .lineLimit(3)
                                                if let song = echo.songInfo {
                                                    Text("♫ \(song)")
                                                        .font(.caption2)
                                                        .foregroundStyle(p.secondaryText)
                                                }
                                            }
                                            .frame(width: 240, alignment: .leading)
                                        }
                                        .onTapGesture {
                                            onEditEntry(echo)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Selected Day Entries
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selectedDate.formatted(date: .long, time: .omitted) + " · \(selectedEntries.count)")
                            .font(.headline)
                            .foregroundStyle(p.primaryText)

                        if selectedEntries.isEmpty {
                            PickupEditorialCard(palette: p, cornerRadius: 18, padding: 18) {
                                Text(isZh ? "这一天没有留下记录。" : "No journal entries on this date.")
                                    .font(.subheadline)
                                    .foregroundStyle(p.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            ForEach(selectedEntries) { entry in
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
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle(s.t("tab_timeline"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenSettings) {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .fullScreenCover(item: $inspectedMedia) { item in
            MediaViewerSheet(store: store, attachments: inspectedEntryMedia, initialAttachment: item)
        }
    }

    private func shiftMonth(by delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayMonth) {
            withAnimation(.spring(response: 0.35)) {
                displayMonth = next
            }
        }
    }

    private func monthTitle(_ date: Date, isZh: Bool) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: isZh ? "zh_CN" : "en_US")
        df.dateFormat = isZh ? "yyyy 年 M 月" : "MMMM yyyy"
        return df.string(from: date)
    }

    private func dateFor(day: Int, in monthDate: Date) -> Date {
        var comps = calendar.dateComponents([.year, .month], from: monthDate)
        comps.day = day
        return calendar.date(from: comps) ?? monthDate
    }

    private func monthCells(for monthDate: Date) -> [Int?] {
        let comps = calendar.dateComponents([.year, .month], from: monthDate)
        guard let startOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return []
        }
        // Monday-first grid: Sunday(1) -> 6, Monday(2) -> 0
        let weekday = calendar.component(.weekday, from: startOfMonth)
        let leadingBlanks = (weekday + 5) % 7
        var cells: [Int?] = Array(repeating: nil, count: leadingBlanks)
        cells.append(contentsOf: range.map { Optional($0) })
        return cells
    }
}
