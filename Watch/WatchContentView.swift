import SwiftUI
import WatchKit

/// 文字盤のコンプリケーションをタップすると開く画面。
/// 開いた瞬間に iPhone へ問い合わせて最新化。リマインダーは○で完了、予定は時刻付きで表示。
struct WatchContentView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let items = FaceComposer.items(session.tasks, at: .now)
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

            Spacer()

            HStack {
                if let error = session.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red).lineLimit(1)
                } else {
                    Text(session.tasks.updatedAt, style: .relative)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    WKInterfaceDevice.current().play(.click)
                    session.requestRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .overlay(alignment: .topTrailing) {
            Text(BuildInfo.marker)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.quaternary)
                .padding(.trailing, 2)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.requestRefresh() }
        }
    }

    @ViewBuilder
    private func row(_ item: FaceItem, index: Int) -> some View {
        switch item.kind {
        case .reminder:
            Button {
                WKInterfaceDevice.current().play(.success)
                session.complete(id: item.id)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(index == 0 ? .headline : .body)
                        .foregroundStyle(FaceStyle.reminder)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)
        case .event:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(item.displayText)
                    .font(index == 0 ? .headline : .body)
                    .foregroundStyle(FaceStyle.event)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }
}
