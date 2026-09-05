import SwiftUI

/// v0: 手打ちの2行を Watch に送るだけ。配管（WC → App Group → ウィジェット再読込）の疎通確認用。
/// v1 でこの画面の入力欄を EventKit の取得結果に差し替える。
struct ContentView: View {
    @EnvironmentObject private var session: PhoneSession
    @State private var first = "iPhone返送"
    @State private var second = "バットテープ巻く"

    var body: some View {
        NavigationStack {
            Form {
                Section("文字盤に出す内容") {
                    TextField("1件目", text: $first)
                    TextField("2件目", text: $second)
                    Button("Watch に送信") {
                        let lines = [first, second].filter { !$0.isEmpty }
                        session.send(FaceTasks(lines: lines, updatedAt: .now))
                    }
                }

                Section("Watch の状態") {
                    row("ペアリング", session.isPaired)
                    row("Watch アプリ", session.isWatchAppInstalled)
                    row("文字盤に配置済み", session.isComplicationEnabled)
                    LabeledContent("残り転送回数 / 日", value: "\(session.remainingTransfers)")
                    LabeledContent("結果", value: session.lastResult)
                        .font(.footnote)
                }
            }
            .navigationTitle("盤面タスク")
            .onAppear { session.refresh() }
        }
    }

    private func row(_ label: String, _ ok: Bool) -> some View {
        LabeledContent(label) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
        }
    }
}
