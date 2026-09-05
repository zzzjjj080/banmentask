import SwiftUI

/// Watch アプリ本体。文字盤からタップした時に開く画面。
/// v0 では受信内容の確認用。v3 でここから完了操作を付ける。
struct WatchContentView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.tasks.lines.isEmpty {
                Text("まだ何も届いていません")
                    .foregroundStyle(.secondary)
                Text("iPhone の盤面タスクから送信してください")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(session.tasks.lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(index == 0 ? .headline : .body)
                        .foregroundStyle(index == 0 ? .primary : .secondary)
                }
                Spacer()
                HStack {
                    Text(session.tasks.updatedAt, style: .relative)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        session.requestRefresh()
                    } label: {
                        Image(systemName: session.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isRefreshing)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.requestRefresh() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .overlay(alignment: .bottomTrailing) {
            Text(BuildInfo.marker)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(4)
        }
    }
}
