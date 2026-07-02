import AppKit
import SwiftUI
import WidgetKit

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CodexQuotaEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
        .widgetURL(WidgetRefreshLink.url)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(entry.snapshot.limits.prefix(2)) { limit in
                WidgetLimitRow(limit: limit)
            }
            Spacer(minLength: 0)
            statusMessage
        }
        .padding(14)
    }

    private var mediumLayout: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                header
                ForEach(entry.snapshot.limits.prefix(2)) { limit in
                    WidgetLimitRow(limit: limit)
                }
                Spacer(minLength: 0)
                statusMessage
            }
            .frame(width: 144)

            VStack(alignment: .leading, spacing: 8) {
                trendHeader

                WidgetTrendChart(points: entry.snapshot.trend)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 2)
            }
            .frame(minWidth: 0, maxWidth: .infinity)
        }
        .padding(.init(top: 16, leading: 18, bottom: 16, trailing: 18))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.green)
            Text("Codex")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer()
            Text(updatedLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.78))
                .accessibilityLabel("点击刷新")
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if entry.snapshot.status != .ready, let message = entry.snapshot.message {
            Text(message)
                .font(.caption2)
                .lineLimit(2)
                .foregroundStyle(entry.snapshot.status == .error ? .red : .secondary)
        }
    }

    private var trendHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("近 5 天趋势")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 2)
                dailyAverageLabel
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("近 5 天趋势")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                dailyAverageLabel
            }
        }
    }

    private var dailyAverageLabel: some View {
        Text("日均 \(TrendCalendar.compactTokenLabel(entry.snapshot.dailyAverageTokens))")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
    }

    private var widgetBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.green.opacity(0.16),
                    Color.cyan.opacity(0.06),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var updatedLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: entry.snapshot.updatedAt)
    }

}

private enum WidgetRefreshLink {
    static let url = URL(string: "codexquota://refresh")!
}

private struct WidgetLimitRow: View {
    var limit: QuotaLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                label
                Spacer(minLength: 4)
                percent
            }

            HStack(spacing: 8) {
                progressBar
                reset
            }
            .frame(height: 11)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.08))
                Capsule()
                    .fill(.green.gradient)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 7)
    }

    private var label: some View {
        Text(limit.label)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.86)
            .allowsTightening(true)
    }

    private var percent: some View {
        Text(percentText)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .allowsTightening(true)
            .frame(minWidth: 48, alignment: .trailing)
            .layoutPriority(2)
    }

    private var reset: some View {
        Text(TrendCalendar.resetLabel(for: limit.resetsAt))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .allowsTightening(true)
            .frame(width: 52, alignment: .trailing)
    }

    private var percentText: String {
        guard let remaining = limit.remainingPercent else {
            return "--"
        }
        return "\(Int(remaining.rounded()))%"
    }

    private var progress: CGFloat {
        CGFloat((limit.remainingPercent ?? 0) / 100)
    }
}

private struct WidgetTrendChart: View {
    var points: [DailyTokenUsage]

    var body: some View {
        GeometryReader { proxy in
            let chartHeight = max(1, proxy.size.height - 18)
            let referenceValue = 100_000_000
            let maxValue = max(points.map(\.tokens).max() ?? 0, referenceValue)
            let plotLeft: CGFloat = 8
            let plotRight: CGFloat = 4
            let plotWidth = max(1, proxy.size.width - plotLeft - plotRight)
            let step = points.count > 1 ? plotWidth / CGFloat(points.count - 1) : plotWidth
            let yForTokens: (Int) -> CGFloat = { tokens in
                let normalized = min(1, max(0, CGFloat(tokens) / CGFloat(maxValue)))
                return chartHeight - normalized * (chartHeight - 8) + 2
            }
            let referenceY = yForTokens(referenceValue)

            ZStack(alignment: .bottomLeading) {
                VStack(spacing: 0) {
                    Color.primary.opacity(0.06).frame(height: 1)
                    Spacer()
                    Color.primary.opacity(0.06).frame(height: 1)
                    Spacer()
                    Color.primary.opacity(0.06).frame(height: 1)
                    Spacer().frame(height: 18)
                }

                Path { path in
                    path.move(to: CGPoint(x: plotLeft, y: referenceY))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: referenceY))
                }
                .stroke(.secondary.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                Text("1亿")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .position(x: plotLeft + 9, y: max(6, referenceY - 7))

                Path { path in
                    for index in points.indices {
                        let x = plotLeft + CGFloat(index) * step
                        let y = yForTokens(points[index].tokens)
                        if index == points.startIndex {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addCurve(
                                to: CGPoint(x: x, y: y),
                                control1: CGPoint(x: x - step * 0.45, y: y),
                                control2: CGPoint(x: x - step * 0.55, y: y)
                            )
                        }
                    }
                }
                .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let x = plotLeft + CGFloat(index) * step
                    let y = yForTokens(point.tokens)
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }

                axisLabels
                .frame(height: 16)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var axisLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                Text(shouldShowAxisLabel(at: index) ? axisLabel(for: point) : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func shouldShowAxisLabel(at index: Int) -> Bool {
        guard !points.isEmpty else {
            return false
        }

        return index == points.startIndex
            || index == points.count / 2
            || index == points.index(before: points.endIndex)
    }

    private func axisLabel(for point: DailyTokenUsage) -> String {
        let pieces = point.dayKey.split(separator: "-")
        guard pieces.count == 3,
              let day = Int(pieces[2]) else {
            return point.label
        }
        return "\(day)日"
    }
}

#if DEBUG
struct QuotaWidgetViewPreviews: PreviewProvider {
    static var previews: some View {
        QuotaWidgetView(entry: CodexQuotaEntry(date: .now, snapshot: previewSnapshot))
            .previewContext(WidgetPreviewContext(family: .systemSmall))

        QuotaWidgetView(entry: CodexQuotaEntry(date: .now, snapshot: previewSnapshot))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }

    static var previewSnapshot: QuotaSnapshot {
        QuotaSnapshot(
            updatedAt: .now,
            status: .ready,
            limits: [
                QuotaLimit(id: "primary", label: "5小时", usedPercent: 63, resetsAt: Date().addingTimeInterval(2_700), windowMinutes: 300),
                QuotaLimit(id: "secondary", label: "周限额", usedPercent: 74, resetsAt: Date().addingTimeInterval(3600 * 24 * 3), windowMinutes: 10_080)
            ],
            trend: [
                DailyTokenUsage(dayKey: "2026-06-09", label: "06-09", tokens: 1_200_000),
                DailyTokenUsage(dayKey: "2026-06-10", label: "06-10", tokens: 3_500_000),
                DailyTokenUsage(dayKey: "2026-06-11", label: "06-11", tokens: 920_000),
                DailyTokenUsage(dayKey: "2026-06-12", label: "06-12", tokens: 5_800_000),
                DailyTokenUsage(dayKey: "2026-06-13", label: "06-13", tokens: 2_100_000)
            ],
            dailyAverageTokens: 2_700_000,
            source: SnapshotSource(rootPath: "~/.codex", scannedFileCount: 12, parsedEventCount: 88, latestEventAt: .now)
        )
    }
}
#endif
