import SwiftUI

/// 純正リマインダーの「文字盤向けフロントエンド」。
/// 見た目は文字盤に合わせて黒地に白。タスク → 接続の状態 → 文字盤プレビューの順。
struct ContentView: View {
    @EnvironmentObject private var session: PhoneSession
    @StateObject private var source = ReminderSource()
    @Environment(\.scenePhase) private var scenePhase

    // 編集中の下書き（id → 文字列）。純正リマインダーと同じく、行をタップしてその場で編集する
    @State private var drafts: [String: String] = [:]
    @FocusState private var focusedID: String?

    // 追加欄
    @State private var isAdding = false
    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    // 完了は猶予つき。○を押すと打ち消し線になり、3秒後に本当に完了する。その間にもう一度押せば取り消し
    @State private var pending: [String: Task<Void, Never>] = [:]
    private let completionGrace: TimeInterval = 3

    @State private var cooldownUntil: Date = .distantPast   // 手動送信の連打防止
    private let cooldown: TimeInterval = 60

    private let bg = Color.black
    private let panel = Color(white: 0.09)
    private let edge = Color(white: 0.18)
    private let dim = Color(white: 0.55)

    var body: some View {
        List {
            // ── リスト切替 ────────────────────────────────────
            Section {
                HStack {
                    listMenu
                    Spacer()
                    modePicker
                }
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 16))
            }

            // ── タスク ────────────────────────────────────────
            Section {
                ForEach(Array(source.items.enumerated()), id: \.element.id) { index, item in
                    taskRow(index: index, item: item)
                        .listRowBackground(bg)
                        .listRowSeparatorTint(edge)
                }
                .onMove { from, to in
                    Haptic.select()
                    Task { await source.move(from: from, to: to) }
                }

                addRow
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))

                sendButton
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
            } footer: {
                if let error = source.errorMessage {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }

            // ── 文字盤プレビュー ──────────────────────────────
            Section {
                watchMock
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
            }

            // ── その他の情報（接続・転送枠・最後の送信）─────────
            Section {
                statusGrid
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 32, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(bg.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Text(BuildInfo.marker)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(white: 0.3))
                .padding(.trailing, 6)
        }
        .environment(\.editMode, .constant(.active))   // 常にドラッグハンドルを出す
        .preferredColorScheme(.dark)
        .tint(.white)
        .scrollDismissesKeyboard(.interactively)
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
        .onChange(of: source.events) { _, _ in send(force: false, reason: "予定") }
        .onChange(of: source.mode) { _, mode in
            if mode.usesCalendar && !source.calendarGranted {
                Task { await source.requestCalendarAccess(); await source.reload() }
            }
            send(force: false, reason: "モード")
        }
        // 編集中の行からフォーカスが外れたら確定
        .onChange(of: focusedID) { old, new in
            if let old, old != new { commitRename(old) }
        }
        // 追加欄からフォーカスが外れて空なら閉じる
        .onChange(of: addFocused) { _, focused in
            if !focused && newTitle.isEmpty { isAdding = false }
        }
    }

    // MARK: - リスト切替

    private var listMenu: some View {
        Menu {
            Picker("リスト", selection: Binding(
                get: { source.listName },
                set: { Haptic.select(); source.listName = $0 }
            )) {
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

    // MARK: - モード切替（文字盤の2行をどう埋めるか）

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(FaceMode.allCases) { m in
                Button {
                    if source.mode != m { Haptic.select(); source.mode = m }
                } label: {
                    Text(m.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(source.mode == m ? .black : dim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(source.mode == m ? Color.white : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(white: 0.16), in: Capsule())
    }

    // MARK: - 文字盤プレビュー（一番下）

    private var watchMock: some View {
        VStack(spacing: 8) {
            WatchMockView(lines: FaceComposer.lines(source.facePayload, at: .now))
            Text("時計ではこう見えます")
                .font(.system(size: 12))
                .foregroundStyle(dim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - タスク行（タップでその場編集、○は3秒の猶予つき完了）

    /// いま文字盤に出ているリマインダーの id
    private var onFaceIDs: Set<String> {
        Set(FaceComposer.items(source.facePayload, at: .now).filter { $0.kind == .reminder }.map(\.id))
    }

    private func taskRow(index: Int, item: ReminderSource.Item) -> some View {
        let isPending = pending[item.id] != nil
        let onFace = onFaceIDs.contains(item.id)
        return HStack(spacing: 14) {
            Button {
                toggleComplete(item)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(onFace ? Color.white : dim, lineWidth: 1.5)
                    if isPending {
                        Circle().fill(.white)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .frame(width: 22, height: 22)
                .animation(.easeOut(duration: 0.15), value: isPending)
            }
            .buttonStyle(.borderless)
            .frame(width: 26)

            TextField("", text: draftBinding(item))
                .font(.system(size: 18, weight: onFace ? .semibold : .regular))
                .foregroundStyle(isPending ? dim : (onFace ? .white : dim))
                .strikethrough(isPending, color: dim)
                .focused($focusedID, equals: item.id)
                .submitLabel(.done)
                .onSubmit { focusedID = nil }
                .disabled(isPending)

            Spacer(minLength: 8)

            if isPending {
                Text("取り消し")
                    .font(.system(size: 12))
                    .foregroundStyle(dim)
            } else if onFace {
                Image(systemName: "applewatch")
                    .font(.system(size: 13))
                    .foregroundStyle(dim)
            }
        }
        .padding(.vertical, 6)
    }

    private func draftBinding(_ item: ReminderSource.Item) -> Binding<String> {
        Binding(
            get: { drafts[item.id] ?? item.title },
            set: { drafts[item.id] = $0 }
        )
    }

    private func commitRename(_ id: String) {
        guard let draft = drafts.removeValue(forKey: id),
              let item = source.items.first(where: { $0.id == id }),
              draft.trimmingCharacters(in: .whitespacesAndNewlines) != item.title
        else { return }
        Haptic.confirm()
        Task { await source.rename(id: id, title: draft) }
    }

    /// ○を押す → 3秒後に完了。その間にもう一度押すと取り消し。
    private func toggleComplete(_ item: ReminderSource.Item) {
        if let task = pending.removeValue(forKey: item.id) {
            task.cancel()
            Haptic.warning()
            return
        }
        Haptic.success()
        pending[item.id] = Task {
            try? await Task.sleep(for: .seconds(completionGrace))
            guard !Task.isCancelled else { return }
            await source.complete(id: item.id)
            pending[item.id] = nil
        }
    }

    // MARK: - 追加（横長の＋ボタン → 押すと入力欄に変わる）

    private var addRow: some View {
        Group {
            if isAdding {
                HStack(spacing: 14) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26)
                    TextField("", text: $newTitle, prompt: Text("タスク名").foregroundStyle(dim))
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .focused($addFocused)
                        .submitLabel(.done)
                        .onSubmit(add)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(edge, lineWidth: 1))
            } else {
                Button {
                    Haptic.tap()
                    isAdding = true
                    addFocused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("追加")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(edge, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 時計に反映（手動送信・60秒クールダウン）

    private var sendButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Int(cooldownUntil.timeIntervalSince(context.date).rounded(.up))
            let waiting = left > 0
            Button {
                Haptic.confirm()
                cooldownUntil = Date.now.addingTimeInterval(cooldown)
                send(force: true, reason: "手動")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: waiting ? "hourglass" : "applewatch")
                    Text(waiting ? "あと \(left) 秒" : "時計に反映")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(waiting ? dim : .black)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(waiting ? Color(white: 0.14) : .white,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(waiting)
        }
    }

    // MARK: - 接続の状態（iPhone → Watch → 文字盤 の経路として見せる）

    private var statusGrid: some View {
        let watchOK = session.isPaired && session.isWatchAppInstalled
        let faceOK = watchOK && session.isComplicationEnabled
        let budget = 50.0
        let remaining = Double(session.remainingTransfers)
        return VStack(spacing: 18) {
            Text("接続")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(dim)
                .tracking(1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            // 経路
            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    node("iphone", label: "iPhone", ok: true)
                    link(ok: watchOK)
                    node("applewatch", label: session.isPaired ? "Watch" : "未ペアリング", ok: watchOK)
                    link(ok: faceOK)
                    node("rectangle.inset.filled", label: faceOK ? "文字盤" : "未配置", ok: faceOK)
                }
                Text(connectionSummary(watchOK: watchOK, faceOK: faceOK))
                    .font(.system(size: 13))
                    .foregroundStyle(faceOK ? Color.green : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 転送枠
            VStack(spacing: 6) {
                HStack {
                    Text("転送枠")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(dim)
                    Spacer()
                    Text("\(session.remainingTransfers)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    + Text(" / 50")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(dim)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(white: 0.18))
                        Capsule()
                            .fill(remaining > 10 ? Color.white : Color.orange)
                            .frame(width: geo.size.width * min(1, remaining / budget))
                    }
                }
                .frame(height: 4)
                Text("文字盤を裏で即時更新できる1日の回数。上位2件が変わった時だけ使う。0になっても文字盤をタップすれば反映される")
                    .font(.system(size: 11))
                    .foregroundStyle(dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(session.lastResult)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .padding(18)
        .background(panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(edge, lineWidth: 1))
    }

    /// いまの接続状態を1行で言う。線が途切れている場所ごとに、何をすればいいかを添える。
    private func connectionSummary(watchOK: Bool, faceOK: Bool) -> String {
        if !session.isPaired { return "Apple Watch とペアリングされていません" }
        if !session.isWatchAppInstalled { return "Watch に盤面タスクが入っていません。iPhone の Watch アプリからインストール" }
        if !session.isComplicationEnabled { return "Watch には届きますが、文字盤に未配置。文字盤を長押し → 編集 → 横長スロットに盤面タスク" }
        return "接続OK。変更は数秒で文字盤に反映されます"
    }

    /// 経路上の1点。丸の中にアイコン、下にラベル。OK なら白、そうでなければ薄く。
    private func node(_ symbol: String, label: String, ok: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(ok ? Color.white : Color.clear)
                    .overlay(Circle().strokeBorder(ok ? Color.white : edge, lineWidth: 1.5))
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ok ? .black : dim)
            }
            .frame(width: 46, height: 46)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ok ? .white : dim)
                .lineLimit(1)
        }
        .frame(width: 84)
    }

    /// 点と点を結ぶ線。通っていれば白、そうでなければ薄い破線風。
    private func link(ok: Bool) -> some View {
        Rectangle()
            .fill(ok ? Color.white : edge)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 26)   // ラベル分だけ上に寄せて丸の中心に合わせる
    }

    // MARK: - 操作

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newTitle = ""
        guard !title.isEmpty else { isAdding = false; return }
        Haptic.confirm()
        Task { await source.add(title: title) }
        addFocused = true   // 続けて入力できるように開いたまま
    }

    private func send(force: Bool, reason: String) {
        let tasks = source.facePayload
        Task { await session.sendIfChanged(tasks, force: force, reason: reason) }
    }
}
