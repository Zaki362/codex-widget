import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var controller: QuotaRefreshController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            limits
            trend
            footer
        }
        .padding(16)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Codex")
                    .font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await controller.refresh() }
            } label: {
                Image(systemName: controller.isRefreshing ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(controller.isRefreshing)
        }
    }

    private var limits: some View {
        VStack(spacing: 10) {
            ForEach(controller.snapshot.limits) { limit in
                MenuQuotaLimitRow(limit: limit)
            }
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("近 5 天趋势")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("日均 \(TrendCalendar.compactTokenLabel(controller.snapshot.dailyAverageTokens))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            MenuTrendChart(points: controller.snapshot.trend)
                .frame(height: 72)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = controller.snapshot.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(controller.snapshot.status == .error ? .red : .secondary)
            }

            HStack(spacing: 8) {
                Button {
                    controller.chooseCodexFolder()
                } label: {
                    Label("授权", systemImage: "folder.badge.gearshape")
                }

                Button {
                    controller.revealSnapshotInFinder()
                } label: {
                    Label("快照", systemImage: "doc.text.magnifyingglass")
                }

                Spacer()

                Toggle("开机启动", isOn: Binding(
                    get: { controller.launchAtLoginEnabled },
                    set: { controller.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                .font(.caption)
            }

            Text(controller.codexFolderURL.path)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.tertiary)
        }
    }

    private var statusLine: String {
        switch controller.snapshot.status {
        case .ready:
            return "更新于 \(updatedTime)"
        case .stale:
            return "数据较旧 · \(updatedTime)"
        case .empty:
            return "等待 Codex 数据"
        case .error:
            return "刷新失败"
        }
    }

    private var updatedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: controller.snapshot.updatedAt)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var controller: QuotaRefreshController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Codex Quota")
                .font(.title2.bold())
            Text("数据目录")
                .font(.headline)
            Text(controller.codexFolderURL.path)
                .font(.callout)
                .textSelection(.enabled)
            HStack {
                Button("选择 .codex 文件夹") {
                    controller.chooseCodexFolder()
                }
                Button("立即刷新") {
                    Task { await controller.refresh() }
                }
            }
            Toggle("开机启动", isOn: Binding(
                get: { controller.launchAtLoginEnabled },
                set: { controller.setLaunchAtLogin($0) }
            ))
        }
    }
}

private struct MenuQuotaLimitRow: View {
    var limit: QuotaLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(limit.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(percentText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(TrendCalendar.resetLabel(for: limit.resetsAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }

            ProgressView(value: limit.remainingPercent ?? 0, total: 100)
                .tint(.green)
        }
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var percentText: String {
        guard let remaining = limit.remainingPercent else {
            return "--"
        }
        return "\(Int(remaining.rounded()))%"
    }
}

private struct MenuTrendChart: View {
    var points: [DailyTokenUsage]

    var body: some View {
        GeometryReader { proxy in
            let maxValue = max(points.map(\.tokens).max() ?? 0, 1)
            let width = proxy.size.width
            let height = proxy.size.height
            let step = points.count > 1 ? width / CGFloat(points.count - 1) : width

            ZStack(alignment: .bottomLeading) {
                Path { path in
                    for index in points.indices {
                        let point = points[index]
                        let x = CGFloat(index) * step
                        let normalized = CGFloat(point.tokens) / CGFloat(maxValue)
                        let y = height - normalized * (height - 12) - 6
                        if index == points.startIndex {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                HStack {
                    ForEach(points) { point in
                        Text(point.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}
