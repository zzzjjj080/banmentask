import SwiftUI

/// 純正リマインダーの「文字盤向けフロントエンド」。
/// 見た目は文字盤に合わせて黒地に白。上に文字盤プレビュー、下にタスク、最後に状態タイル。
struct ContentView: View {
    @EnvironmentObject private var session: PhoneSession
    @StateObject private var source = ReminderSource()
    @Environment(\.scenePhase) private var scenePhase

    @State private var newTitle = ""
    @State private var renaming: ReminderSource.Item?
    @State private var renameTitle = ""

    private let bg = Color.black
    private let panel = Color(white: 0.09)
    private let edge = Color(white: 0.18)
    private let dim = Color(white: 0.55)

    var body: some View {
        List {
            // ── 文字盤プレビュー ──────────────────────────────
            Section {
                facePreview
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }

            // ── タスク ────────────────────────────────────────
            Section {
                ForEach(Array(source.items.enumerated()), id: \.element.id) { index, item in
                    taskRow(index: index, item: item)
                        .listRowBackground(bg)
                        .listRowSeparatorTint(edge)
                }
                .onMove { from, to in
                    Task { await source.move(from: from, to: to) }
                }

                // 追加欄は並びの一番下
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(dim)
                        .frame(width: 26)
                    TextField("", text: $newTitle, prompt: Text("追加").foregroundStyle(dim))
                        .foregroundStyle(.white)
                        .submitLabel(.done)
                        .onSubmit(add)
                }
                .padding(.vertical, 4)
                .listRowBackground(bg)
                .listRowSeparator(.hidden)
            } footer: {
                if let error = source.errorMessage {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }

            // ── Watch の状態（2列タイル）──────────────────────
            Section {
                statusGrid
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 24, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(bg.ignoresSafeArea())
        .environment(\.editMode, .constant(.active))   // 常にドラッグハンドルを出す
        .preferredColorScheme(.dark)
        .tint(.white)
        .alert("タイトルを変更", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("タイトル", text: $renameTitle)
            Button("保存") {
                if let item = renaming {
                    Task { await source.rename(id: item.id, title: renameTitle) }
                }
                renaming = nil
            }
            Button("キャンセル", role: .cancel) { renaming = nil }
        }
        .task { await source.requestAccess() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                session.refresh()
                Task { await source.reload() }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
        .onChange(of: source.items) { _, _ in send(force: false, reason: "画面") }
    }

    // MARK: - 文字盤プレビュー

    private var facePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WATCH FACE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(dim)
                    .tracking(1.5)
                Spacer()
                listMenu
            }
            VStack(alignment: .leading, spacing: 4) {
                let lines = source.faceTasks.lines
                Text(lines.first ?? "タスクなし")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(lines.isEmpty ? dim : .white)
                    .lineLimit(1)
                Text(lines.count > 1 ? lines[1] : " ")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(dim)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(edge, lineWidth: 1))
    }

    private var listMenu: some View {
        Menu {
            Picker("リスト", selection: $source.listName) {
                ForEach(source.listNames, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(source.listName)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(dim)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(white: 0.16), in: Capsule())
        }
    }

    // MARK: - タスク行

    private func taskRow(index: Int, item: ReminderSource.Item) -> some View {
        HStack(spacing: 14) {
            Button {
                Task { await source.complete(id: item.id) }
            } label: {
                Circle()
                    .strokeBorder(index < 2 ? Color.white : dim, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .frame(width: 26)

            Text(item.title)
                .font(.system(size: 18, weight: index < 2 ? .semibold : .regular))
                .foregroundStyle(index < 2 ? .white : dim)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture {
                    renameTitle = item.title
                    renaming = item
                }

            Spacer(minLength: 8)

            if index < 2 {
                Image(systemName: "applewatch")
                    .font(.system(size: 13))
                    .foregroundStyle(dim)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - 状態タイル

    private var statusGrid: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("ペアリング", ok: session.isPaired)
                tile("WATCH アプリ", ok: session.isWatchAppInstalled)
                tile("文字盤に配置", ok: session.isComplicationEnabled)
                tile("残り転送 / 日", value: "\(session.remainingTransfers)")
                tile("ビルド", value: BuildInfo.marker)
                Button {
                    send(force: true, reason: "手動")
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.forward.app")
                        Text("いま送る")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Text(session.lastResult)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
    }

    private func tile(_ label: String, ok: Bool) -> some View {
        tileBody(label) {
            Image(systemName: ok ? "checkmark" : "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ok ? Color.green : Color.red)
        }
    }

    private func tile(_ label: String, value: String) -> some View {
        tileBody(label) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private func tileBody<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(dim)
                .tracking(0.5)
            Spacer()
            value()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(edge, lineWidth: 1))
    }

    // MARK: - 操作

    private func add() {
        let title = newTitle
        newTitle = ""
        Task { await source.add(title: title) }
    }

    private func send(force: Bool, reason: String) {
        let tasks = source.faceTasks
        Task { await session.sendIfChanged(tasks, force: force, reason: reason) }
    }
}
