import SwiftUI

/// Watch アプリ本体。文字盤からタップした時に開く画面。
/// v0 では受信内容の確認用。v3 でここから完了操作を付ける。
struct WatchContentView: View {
    @EnvironmentObject private var session: WatchSession

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
                Text(session.tasks.updatedAt, style: .relative)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
