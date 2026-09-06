import SwiftUI

/// 文字盤のコンプリケーションをタップすると開く画面。
/// 開いた瞬間に iPhone へ問い合わせて最新化し、○で完了できる。
struct WatchContentView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.tasks.lines.isEmpty {
                Text("タスクなし")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("iPhone の盤面タスクで追加してください")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(session.tasks.lines.enumerated()), id: \.offset) { index, line in
                    let id = index < session.tasks.ids.count ? session.tasks.ids[index] : nil
                    Button {
                        if let id { session.complete(id: id) }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(line)
                                .font(index == 0 ? .headline : .body)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(id == nil || session.isBusy)
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
}
