import WidgetKit
import SwiftUI

// MARK: - タイムライン

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: FaceTasks
}

struct TaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: .now, tasks: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        // 文字盤編集画面のプレビューではダミーを出す
        let tasks: FaceTasks = context.isPreview ? .placeholder : TaskStore.load()
        completion(TaskEntry(date: .now, tasks: tasks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = TaskEntry(date: .now, tasks: TaskStore.load())
        // データ更新時は WatchSession が reloadAllTimelines() を呼ぶので、
        // ここは保険として1時間後に再読込するだけ。
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - 表示

struct BanmenTaskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskEntry

    private var first: String { entry.tasks.first.isEmpty ? "タスクなし" : entry.tasks.first }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular
        case .accessoryInline:
            Text(first)
        case .accessoryCorner:
            Image(systemName: "checklist")
                .widgetLabel(first)
        default:
            Image(systemName: "checklist")
        }
    }

    /// 本命。モジュラー / インフォグラフ モジュラー の横長スロット。
    /// ヘッダ無し・2行構成。1件目を大きく、2件目を控えめに。
    /// 2行とも同じフォントで、枠に入る最大サイズ。長い文言は縮めて1行に収める。
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            line(first)
            if !entry.tasks.second.isEmpty {
                line(entry.tasks.second)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - ウィジェット定義

@main
struct BanmenTaskWidget: Widget {
    let kind = "BanmenTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskProvider()) { entry in
            BanmenTaskWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("盤面タスク")
        .description("リマインダーの上位2件を表示")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCorner, .accessoryCircular])
    }
}
