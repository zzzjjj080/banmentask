import WidgetKit
import SwiftUI
import EventKit

// MARK: - データ

struct HomeEntry: TimelineEntry {
    let date: Date
    let listName: String
    let items: [HomeItem]
    let layout: FaceLayout
}

struct HomeItem: Identifiable {
    let id: String
    let title: String
}

/// ウィジェット拡張から直接 EventKit を読む。本体アプリで許可済みなら extension からも読める。
///
/// **このウィジェットは読むだけ。** 完了させる機能は持たない（b33 で外した）。
/// チェックの当たり判定に幅を取られていたのを、点にして題名へ回すため。
enum HomeReminders {
    static func load(listName: String, limit: Int) -> [HomeItem] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return [] }
        let store = EKEventStore()
        guard let calendar = store.calendars(for: .reminder).first(where: { $0.title == listName }) else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [calendar])
        let sem = DispatchSemaphore(value: 0)
        var found: [EKReminder] = []
        store.fetchReminders(matching: predicate) { found = $0 ?? []; sem.signal() }
        _ = sem.wait(timeout: .now() + 5)
        return found
            .sorted { a, b in
                let pa = a.priority == 0 ? Int.max : a.priority
                let pb = b.priority == 0 ? Int.max : b.priority
                if pa != pb { return pa < pb }
                return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
            }
            .prefix(limit)
            .map { HomeItem(id: $0.calendarItemIdentifier, title: $0.title ?? "") }
    }
}

// MARK: - タイムライン

struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(date: .now, listName: "基本",
                  items: [HomeItem(id: "1", title: "洗濯する"),
                          HomeItem(id: "2", title: "電話する"),
                          HomeItem(id: "3", title: "牛乳を買う")],
                  layout: .default)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(for: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let e = entry(for: context)
        completion(Timeline(entries: [e],
                            policy: .after(Calendar.current.date(byAdding: .minute, value: 15, to: .now)!)))
    }

    private func entry(for context: Context) -> HomeEntry {
        // 多めに読んで、表示側が実際に収まる件数まで削る
        let limit: Int
        switch context.family {
        case .systemLarge: limit = 22
        case .systemMedium: limit = 12
        default: limit = 7
        }
        let listName = LayoutStore.listName
        return HomeEntry(date: .now, listName: listName,
                         items: HomeReminders.load(listName: listName, limit: limit),
                         layout: LayoutStore.load())
    }
}

// MARK: - 見た目（見出しなし、収まる分だけ、上下の中央に置く）

/// 行の寸法。ここだけで決めて、収まる件数の計算と実際の描画の両方で使う。
///
/// 文字の大きさは件数で決まる。**満杯なら 15pt、少なければ空いたぶん大きくして埋める**（最大 19pt）。
private enum Metric {
    static let minFont: CGFloat = 15
    static let maxFont: CGFloat = 19
    /// 実際の行の高さは文字の 1.2 倍ほど。計算は少し多めに見て、最後の行がはみ出さないようにする
    static let lineRatio: CGFloat = 1.25
    static let rowGap: CGFloat = 3           // 行と行のあいだ
    static let gap: CGFloat = 6              // 点と題名のあいだ
    static let padLeading: CGFloat = 8
    static let padTrailing: CGFloat = 6
    static let padVertical: CGFloat = 7

    static func lineHeight(_ font: CGFloat) -> CGFloat { (font * lineRatio).rounded() }
    static func dot(_ font: CGFloat) -> CGFloat { (font * 0.33).rounded() }
    static func dotSlot(_ font: CGFloat) -> CGFloat { dot(font) + 4 }
}

private struct Plan {
    let items: [HomeItem]
    let font: CGFloat
    let lineLimit: Int
}

struct HomeWidgetView: View {
    let entry: HomeEntry

    var body: some View {
        Group {
            if entry.items.isEmpty {
                Text(EKEventStore.authorizationStatus(for: .reminder) == .fullAccess ? "タスクなし" : "盤面タスクを一度開いて許可してください")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let plan = plan(for: geo.size)
                    VStack(alignment: .leading, spacing: Metric.rowGap) {
                        ForEach(plan.items) { item in
                            row(item, plan: plan)
                        }
                    }
                    // 余りは上下に均等に配る。上だけ詰まって下が空くのを避ける
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
        }
        // 既定の余白（16pt）は contentMarginsDisabled で外してある。ここが実際の余白
        .padding(.leading, Metric.padLeading)
        .padding(.trailing, Metric.padTrailing)
        .padding(.vertical, Metric.padVertical)
        .containerBackground(.black, for: .widget)
    }

    // MARK: - 収まる件数を決める

    /// 件数を優先する。いちばん小さい文字で入る件数をまず出し、
    /// **件数がそれに満たないぶんは文字を大きくして埋める。**
    /// そのうえで、2行に伸ばしても収まる時だけ2行を許す。
    /// 収まらないなら題名を1行に切って（右端を落として）件数を保つ。
    private func plan(for size: CGSize) -> Plan {
        let base = Metric.lineHeight(Metric.minFont)
        let maxCount = max(1, Int((size.height + Metric.rowGap) / (base + Metric.rowGap)))
        let items = Array(entry.items.prefix(maxCount))
        let count = CGFloat(max(1, items.count))

        // 空いたぶんだけ文字を大きくする
        let fill = (size.height - (count - 1) * Metric.rowGap) / count
        let font = min(Metric.maxFont, max(Metric.minFont, fill / Metric.lineRatio))

        let lineHeight = Metric.lineHeight(font)
        let textWidth = size.width - Metric.dotSlot(font) - Metric.gap
        let needed = items.reduce(CGFloat.zero) { total, item in
            let lines: CGFloat = estimatedWidth(item.title, font: font) <= textWidth ? 1 : 2
            return total + lines * lineHeight
        } + (count - 1) * Metric.rowGap
        return Plan(items: items, font: font, lineLimit: needed <= size.height ? 2 : 1)
    }

    /// 題名の幅の見当。全角はフォントの大きさ、半角はその半分強で数える。
    private func estimatedWidth(_ title: String, font: CGFloat) -> CGFloat {
        title.unicodeScalars.reduce(CGFloat.zero) { width, scalar in
            width + (scalar.value < 0x2E80 ? font * 0.55 : font)
        }
    }

    // MARK: - 1行

    private func row(_ item: HomeItem, plan: Plan) -> some View {
        let dot = Metric.dot(plan.font)
        return HStack(alignment: .top, spacing: Metric.gap) {
            Circle()
                .fill(Color(white: 0.45))
                .frame(width: dot, height: dot)
                .frame(width: Metric.dotSlot(plan.font), alignment: .leading)
                // 1行目の高さの真ん中に点を置く
                .padding(.top, (Metric.lineHeight(plan.font) - dot) / 2)

            Text(item.title)
                .font(.system(size: plan.font, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(plan.lineLimit)
                .truncationMode(.tail)          // 入らない分は右端を落とす
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 定義

struct BanmenTaskHomeWidget: Widget {
    static let kind = "BanmenTaskHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: HomeProvider()) { entry in
            HomeWidgetView(entry: entry)
        }
        .configurationDisplayName("盤面タスク")
        .description("リマインダーの上から順にホーム画面へ表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // 既定の余白（16pt）を外して自分で詰める。上と左をもう少し使うため
        .contentMarginsDisabled()
    }
}

@main
struct BanmenTaskHomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        BanmenTaskHomeWidget()
    }
}
