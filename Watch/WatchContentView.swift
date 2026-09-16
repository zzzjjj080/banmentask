import SwiftUI
import WatchKit

/// 文字盤のコンプリケーションをタップすると開く画面。
/// 開いた瞬間に iPhone へ問い合わせて最新化。リマインダーは○で完了、予定は時刻付きで表示。
struct WatchContentView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.scenePhase) private var scenePhase

    /// ○を押してから実際に完了させるまでの猶予。id → 完了する時刻
    /// （押し間違えても、もう一度押せば取り消せる。秒数は iPhone 側と同じ）
    @State private var pending: [String: Date] = [:]
    @State private var timers: [String: Task<Void, Never>] = [:]

    var body: some View {
        let items = FaceComposer.items(session.tasks, at: .now)
        // 画面に収まらない分（版の表示など）まで届くようにスクロールさせる
        ScrollView {
        VStack(alignment: .leading, spacing: 6) {
            if items.isEmpty {
                Text(session.tasks.layout.usesReminders ? "タスクなし" : "予定なし")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("iPhone の盤面タスクで追加してください")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                }
            }

            if let error = session.lastError {
                Text(error).font(.footnote).foregroundStyle(.orange).lineLimit(2)
            } else if !pending.isEmpty {
                Text("もう一度タップで取り消し")
                    .font(.footnote)
                    .foregroundStyle(FaceStyle.color(.reminder, layout: session.tasks.layout))
            } else {
                Text(session.tasks.updatedAt, style: .relative)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Button {
                WKInterfaceDevice.current().play(.click)
                session.requestRefresh()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: session.isBusy ? "hourglass" : "arrow.clockwise")
                    Text(session.isBusy ? "更新中…" : "iPhone から更新")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(white: 0.25))
            .disabled(session.isBusy)

            // どのビルドが入っているか（いちばん下）
            Text(BuildInfo.line)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.requestRefresh() }
        }
        #if DEBUG
        // 猶予中の見た目を撮るため。BT_PENDING=1 で開いた直後に1件を猶予状態にする
        .task {
            guard ProcessInfo.processInfo.environment["BT_PENDING"] == "1" else { return }
            if let first = FaceComposer.items(session.tasks, at: .now).first(where: { $0.kind == .reminder }) {
                startCompleting(first)
            }
        }
        #endif
    }

    @ViewBuilder
    private func row(_ item: FaceItem, index: Int) -> some View {
        switch item.kind {
        case .reminder:
            let deadline = pending[item.id]
            let waiting = deadline != nil
            let tint = FaceStyle.color(.reminder, layout: session.tasks.layout)
            // 行ぜんぶが押す場所。小さい画面でも取り消しやすいように
            Button {
                waiting ? cancel(item.id) : startCompleting(item)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: waiting ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(waiting ? tint : .secondary)
                    Text(item.title)
                        .font(index == 0 ? .headline : .body)
                        .foregroundStyle(waiting ? Color.secondary : tint)
                        .strikethrough(waiting, color: .secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let deadline {
                        // 残り時間が減るリング。この間にもう一度押せば取り消し
                        ProgressView(timerInterval: deadline.addingTimeInterval(-PendingStore.grace)...deadline,
                                     countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                            .progressViewStyle(.circular)
                            .tint(tint)
                            .frame(width: 20, height: 20)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy && !waiting)
        case .event:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(item.displayText)
                    .font(index == 0 ? .headline : .body)
                    .foregroundStyle(FaceStyle.color(.event, layout: session.tasks.layout))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - 完了の猶予

    /// ○を押した。すぐには消さず、猶予のあいだ待ってから iPhone へ「完了して」と送る
    private func startCompleting(_ item: FaceItem) {
        WKInterfaceDevice.current().play(.click)
        pending[item.id] = Date.now.addingTimeInterval(PendingStore.grace)
        timers[item.id]?.cancel()
        timers[item.id] = Task {
            try? await Task.sleep(for: .seconds(PendingStore.grace))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard pending[item.id] != nil else { return }
                pending[item.id] = nil
                timers[item.id] = nil
                WKInterfaceDevice.current().play(.success)
                session.complete(id: item.id)
            }
        }
    }

    /// 猶予のあいだにもう一度押した。完了させない
    private func cancel(_ id: String) {
        WKInterfaceDevice.current().play(.retry)
        timers[id]?.cancel()
        timers[id] = nil
        pending[id] = nil
    }
}
