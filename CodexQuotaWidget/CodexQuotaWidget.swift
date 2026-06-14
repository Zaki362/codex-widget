import SwiftUI
import WidgetKit

struct CodexQuotaEntry: TimelineEntry {
    var date: Date
    var snapshot: QuotaSnapshot
}

struct CodexQuotaTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CodexQuotaEntry {
        CodexQuotaEntry(date: Date(), snapshot: .placeholder())
    }

    func getSnapshot(in context: Context, completion: @escaping (CodexQuotaEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CodexQuotaEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: entry.date) ?? entry.date.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> CodexQuotaEntry {
        let now = Date()
        let snapshot = (try? QuotaSnapshotStore.defaultStore().load().markingStaleIfNeeded(now: now)) ?? .placeholder(now: now)
        return CodexQuotaEntry(date: now, snapshot: snapshot)
    }
}

struct CodexQuotaWidget: Widget {
    let kind = "CodexQuotaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CodexQuotaTimelineProvider()) { entry in
            QuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 额度")
        .description("显示 Codex 额度、刷新时间与 token 趋势")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

@main
struct CodexQuotaWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexQuotaWidget()
    }
}
