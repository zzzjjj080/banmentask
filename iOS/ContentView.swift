import SwiftUI

/// v1/v2: EventKit から読んだリストを表示し、ドラッグで並べ替えると
/// priority に焼き込まれ、上位2件が Watch へ送られる。
struct ContentView: View {
    @EnvironmentObject private var session: PhoneSession
    @StateObject private var source = ReminderSource()
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastSentLines: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if source.items.isEmpty {
                        Text(source.accessGranted ? "未完了のタスクがありません" : "リマインダーへのアクセスを許可してください")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(source.items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 20, alignment: .trailing)
                            Text(item.title)
                                .fontWeight(index < 2 ? .semibold : .regular)
                            Spacer()
                            if index < 2 {
                                Image(systemName: "applewatch")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .onMove { from, to in
                        Task { await source.move(from: from, to: to) }
                    }
                } header: {
                    Text("上位2件が文字盤に出ます。ドラッグで並べ替え")
                } footer: {
                    if let error = source.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section("Watch の状態") {
                    row("ペアリング", session.isPaired)
                    row("Watch アプリ", session.isWatchAppInstalled)
                    row("文字盤に配置済み", session.isComplicationEnabled)
                    LabeledContent("残り転送回数 / 日", value: "\(session.remainingTransfers)")
                    LabeledContent("結果", value: session.lastResult).font(.footnote)
                    Button("いますぐ Watch に送信") { send(force: true) }
                }
            }
            .environment(\.editMode, .constant(.active))   // 常にドラッグハンドルを出す
            .navigationTitle("盤面タスク")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("リスト", selection: $source.listName) {
                            ForEach(source.listNames, id: \.self) { Text($0).tag($0) }
                        }
                    } label: {
                        Label(source.listName, systemImage: "list.bullet")
                    }
                }
            }
            .task { await source.requestAccess() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    session.refresh()
                    Task { await source.reload() }
                }
            }
            .onChange(of: source.items) { _, _ in send(force: false) }
        }
    }

    /// 上位2件が変わった時だけ送る（1日50回の転送枠を無駄にしない）
    private func send(force: Bool) {
        let tasks = source.faceTasks
        guard force || tasks.lines != lastSentLines else { return }
        lastSentLines = tasks.lines
        session.send(tasks)
    }

    private func row(_ label: String, _ ok: Bool) -> some View {
        LabeledContent(label) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
        }
    }
}
