import WidgetKit
import SwiftUI

struct TaskEntry: TimelineEntry {
    let date: Date
    let payload: FacePayload

    var lines: [String] { FaceComposer.lines(payload, at: date) }
}

struct TaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: .now, payload: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(TaskEntry(date: .now, payload: context.isPreview ? .placeholder : TaskStore.load()))
    }

    /// データ更新時は WatchSession 側が reloadAllTimelines() を呼ぶ。
    /// ここでは「予定の開始時刻」ごとにエントリを刻み、時間が来たら iPhone に頼らず自分で切り替える。
    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let payload = TaskStore.load()
        let now = Date.now
        var dates = [now] + FaceComposer.changePoints(payload, after: now).map { $0.addingTimeInterval(1) }
        // 保険として1時間後にも読み直す
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        dates.append(next)
        let entries = dates.sorted().map { TaskEntry(date: $0, payload: payload) }
        completion(Timeline(entries: entries, policy: .after(next)))
    }
}

struct BanmenTaskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskEntry

    private var first: String { entry.lines.first ?? "" }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text(first.isEmpty ? "タスクなし" : first)
        case .accessoryCorner:
            Image(systemName: "checklist")
                .widgetLabel(first)
        default:
            Image(systemName: "checklist")
        }
    }

    /// 2行を1つの Text にまとめて縮める。
    /// 別々の Text にすると長い行だけ縮んでサイズが揃わないため、
    /// 改行で繋いだ1つの Text に lineLimit をかけ、長い方に合わせて両方を同じ倍率で縮める。
    private var rectangular: some View {
        let lines = entry.lines
        return Text(lines.isEmpty ? "タスクなし" : lines.joined(separator: "\n"))
            .font(.system(size: 24, weight: .semibold))
            .lineLimit(max(1, lines.count))
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

@main
struct BanmenTaskWidget: Widget {
    let kind = "BanmenTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskProvider()) { entry in
            BanmenTaskWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("盤面タスク")
        .description("リマインダーと今日の予定を文字盤に")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCorner, .accessoryCircular])
    }
}
