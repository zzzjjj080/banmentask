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

    // 完了は猶予つき。○を押すと打ち消し線になり、5秒後に本当に完了する。その間にもう一度押せば取り消し
    @State private var pending: [String: Task<Void, Never>] = [:]
    @State private var pendingSince: [String: Date] = [:]
    private let completionGrace: TimeInterval = PendingStore.grace

    @State private var cooldownUntil: Date = .distantPast   // 手動送信の連打防止

    // 投げ銭。製品IDは App Store Connect と1文字違わず合わせる
    @State private var tipJar = TipJar(productID: "com.zzzjjj080.banmentask.coffee")
    private let cooldown: TimeInterval = 60

    private let bg = Color.black
    private let panel = Color(white: 0.09)
    private let edge = Color(white: 0.18)
    private let dim = Color(white: 0.55)

    var body: some View {
        List {
            // ── リスト切替 ────────────────────────────────────
            Section {
                HStack { listMenu; Spacer() }
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
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
            } footer: {
                if let error = source.errorMessage {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }

            // ── 時計に反映 → 文字盤プレビュー → 表示設定 ─────────
            Section {
                watchMock
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }

            // ── その他の情報（接続・転送枠・最後の送信）─────────
            Section {
                statusGrid
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    // 時計まわりより重要度が低いので、間を空けて下げる
                    .listRowInsets(EdgeInsets(top: 48, leading: 16, bottom: 6, trailing: 16))
                CoffeeTipSection(tipJar: tipJar)
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 6, trailing: 16))
                Text(BuildInfo.marker)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.3))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .listRowBackground(bg)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 32, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(bg.ignoresSafeArea())
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
        .onChange(of: source.layout) { _, layout in
            if layout.usesCalendar && !source.calendarGranted {
                Task { await source.requestCalendarAccess(); await source.reload() }
            }
            send(force: false, reason: "表示設定")
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

    // MARK: - 件数と色（時計の右のカード）

    @State private var showLimitAlert = false
    @State private var colorPickerFor: FaceItem.Kind?

    private func slots(_ kind: FaceItem.Kind) -> Int {
        kind == .reminder ? source.layout.reminderSlots : source.layout.calendarSlots
    }

    private func step(_ kind: FaceItem.Kind, _ delta: Int) {
        change(reminders: source.layout.reminderSlots + (kind == .reminder ? delta : 0),
               calendar: source.layout.calendarSlots + (kind == .event ? delta : 0))
    }

    private func change(reminders: Int, calendar: Int) {
        guard reminders >= 0, calendar >= 0, reminders + calendar >= 1 else { return }
        guard reminders + calendar <= FaceLayout.maxLines else {
            Haptic.warning()
            showLimitAlert = true
            return
        }
        Haptic.select()
        source.layout = FaceLayout(reminders: reminders, calendar: calendar,
                                   reminderColor: source.layout.reminderColor, eventColor: source.layout.eventColor)
    }

    /// 上段「リマインダー　● 白 ▾」、下段「−　2　＋」。色は押すと15色の一覧が開く
    private func slotCard(_ kind: FaceItem.Kind) -> some View {
        let value = slots(kind)
        let total = source.layout.lines
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(kind == .reminder ? "リマインダー" : "予定")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                colorChip(kind)
            }
            HStack(spacing: 0) {
                stepButton("minus", enabled: value > 0 && total > 1) { step(kind, -1) }
                Text("\(value)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                stepButton("plus", enabled: total < FaceLayout.maxLines) { step(kind, +1) }
            }
            .frame(height: 42)
            .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(10)
        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(edge, lineWidth: 1))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 46, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.white : Color(white: 0.35))
    }

    /// 今の色を「● 白 ▾」と名前つきで見せる。押すと色の一覧
    private func colorChip(_ kind: FaceItem.Kind) -> some View {
        let index = source.layout.color(kind)
        return Button {
            Haptic.select()
            colorPickerFor = kind
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(FaceStyle.color(index))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    .frame(width: 14, height: 14)
                Text(FaceStyle.name(index))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color(white: 0.17), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { colorPickerFor == kind },
                                      set: { if !$0 { colorPickerFor = nil } })) {
            colorGrid(kind)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func colorGrid(_ kind: FaceItem.Kind) -> some View {
        let current = source.layout.color(kind)
        return VStack(alignment: .leading, spacing: 12) {
            Text(kind == .reminder ? "リマインダーの色" : "予定の色")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(dim)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 6), count: 5), spacing: 10) {
                ForEach(FaceStyle.palette.indices, id: \.self) { i in
                    Button { pick(i, for: kind) } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(FaceStyle.color(i))
                                .overlay(Circle().strokeBorder(i == current ? Color.white : Color.white.opacity(0.2),
                                                               lineWidth: i == current ? 2.5 : 1))
                                .frame(width: 30, height: 30)
                            Text(FaceStyle.name(i))
                                .font(.system(size: 10, weight: i == current ? .semibold : .regular))
                                .foregroundStyle(i == current ? Color.white : dim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .preferredColorScheme(.dark)
    }

    private func pick(_ index: Int, for kind: FaceItem.Kind) {
        Haptic.select()
        var l = source.layout
        if kind == .reminder { l.reminderColor = index } else { l.eventColor = index }
        source.layout = l
        colorPickerFor = nil
    }

    // MARK: - 文字盤プレビュー（左）と件数・色（右）

    private static let mockScale: CGFloat = 0.74

    private var watchMock: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(spacing: 0) {
                feed
                WatchMockView(lines: FaceComposer.exampleLines(source.layout), layout: source.layout)
                    .scaleEffect(Self.mockScale, anchor: .top)
                    .frame(width: WatchMockView.size.width * Self.mockScale,
                           height: WatchMockView.size.height * Self.mockScale, alignment: .top)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("表示設定")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(dim)
                slotCard(.reminder)
                slotCard(.event)
            }
            .frame(maxWidth: .infinity)
        }
        .alert("文字盤には合計 \(FaceLayout.maxLines) 件までです", isPresented: $showLimitAlert) {
            Button("OK", role: .cancel) {}
        }
    }

    /// 上の一覧から時計への流れ：流れる矢印 → 今すぐ反映 → 「変更は自動で反映されます」→ 時計
    private var feed: some View {
        VStack(spacing: 0) {
            FlowDown()
            sendButton
                .padding(.top, 6)
            Text("変更は自動で反映されます")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(dim)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 7)
            // 説明から時計の上縁へつなぐ短い線
            LinearGradient(colors: [Color(white: 0.4), Color(white: 0.2)], startPoint: .top, endPoint: .bottom)
                .frame(width: 2, height: 12)
                .padding(.top, 4)
        }
        .frame(width: WatchMockView.size.width * Self.mockScale)
    }

    // MARK: - タスク行（タップでその場編集、○は5秒の猶予つき完了）

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
                        .strokeBorder(onFace ? FaceStyle.color(source.layout.reminderColor) : dim, lineWidth: 1.5)
                    if isPending {
                        Circle().fill(FaceStyle.color(source.layout.reminderColor))
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
                countdown(for: item.id)
            } else if onFace {
                Image(systemName: "applewatch")
                    .font(.system(size: 13))
                    .foregroundStyle(dim)
            }
        }
        .padding(.vertical, 6)
    }

    /// 完了までのカウントダウン。リングが5秒かけて減り、中に残り秒数。押せば取り消し
    private func countdown(for id: String) -> some View {
        HStack(spacing: 8) {
            Text("取り消し")
                .font(.system(size: 12))
                .foregroundStyle(dim)
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let since = pendingSince[id] ?? context.date
                let elapsed = context.date.timeIntervalSince(since)
                let remaining = max(0, completionGrace - elapsed)
                ZStack {
                    Circle()
                        .stroke(edge, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: remaining / completionGrace)
                        .stroke(FaceStyle.color(source.layout.reminderColor), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .frame(width: 24, height: 24)
            }
        }
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

    /// ○を押す → 5秒後に完了。その間にもう一度押すと取り消し。
    private func toggleComplete(_ item: ReminderSource.Item) {
        if let task = pending.removeValue(forKey: item.id) {
            task.cancel()
            pendingSince[item.id] = nil
            Haptic.warning()
            return
        }
        Haptic.success()
        pendingSince[item.id] = .now
        pending[item.id] = Task {
            try? await Task.sleep(for: .seconds(completionGrace))
            guard !Task.isCancelled else { return }
            await source.complete(id: item.id)
            pending[item.id] = nil
            pendingSince[item.id] = nil
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

    // MARK: - 今すぐ反映（手動送信・60秒クールダウン。ふだんは自動で送っている）

    private var sendButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = Int(cooldownUntil.timeIntervalSince(context.date).rounded(.up))
            let waiting = left > 0
            Button {
                Haptic.confirm()
                cooldownUntil = Date.now.addingTimeInterval(cooldown)
                send(force: true, reason: "手動")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: waiting ? "hourglass" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .bold))
                    Text(waiting ? "あと \(left) 秒" : "今すぐ反映")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(waiting ? dim : Color.black)
            }
            .buttonStyle(KeycapButtonStyle(enabled: !waiting))
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

/// 上から下へ流れる矢印。明るい所が上から下へ移っていく（「視差効果を減らす」なら止める）
private struct FlowDown: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, Color(white: 0.4)], startPoint: .top, endPoint: .bottom)
                    .frame(width: 2, height: 16)
                VStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { i in
                        let wave = reduceMotion ? 0.6 : 0.5 + 0.5 * sin(2 * Double.pi * (t * 0.9 - Double(i) * 0.28))
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.18 + 0.62 * wave))
                    }
                }
            }
        }
    }
}

/// 押せると分かるキーの形。下に厚みがあり、押すと沈む
private struct KeycapButtonStyle: ButtonStyle {
    var enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && enabled
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                shape.fill(enabled
                           ? LinearGradient(colors: [Color.white, Color(white: 0.84)], startPoint: .top, endPoint: .bottom)
                           : LinearGradient(colors: [Color(white: 0.22), Color(white: 0.18)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.strokeBorder(Color.white.opacity(enabled ? 0.9 : 0.08), lineWidth: 1))
            .offset(y: pressed ? 4 : 0)
            .background(
                // 厚みの部分
                shape.fill(enabled ? Color(white: 0.45) : Color(white: 0.12))
                    .offset(y: 4)
            )
            .padding(.bottom, 4)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}
