#!/usr/bin/env swift
//
// ReminderProbe.swift
//
// 「純正リマインダーの手動並び順を priority(1-9) で代替できるか」を検証するツール。
// Mac mini のターミナルで実行する。Xcode プロジェクト不要。
//
//   swift ReminderProbe.swift lists
//   swift ReminderProbe.swift dump   基本
//   swift ReminderProbe.swift spread 基本
//   swift ReminderProbe.swift set    基本 3 1
//   swift ReminderProbe.swift clear  基本
//   swift ReminderProbe.swift probe  基本
//
// 初回実行時に「ターミナルがリマインダーへのアクセスを求めています」が出るので許可する。
//

import Foundation
import EventKit
import ObjectiveC.runtime

let store = EKEventStore()

func die(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

// MARK: - アクセス許可

func requestAccess() -> Bool {
    let sem = DispatchSemaphore(value: 0)
    var granted = false
    let handler: EKEventStoreRequestAccessCompletionHandler = { ok, err in
        granted = ok
        if let err { FileHandle.standardError.write("access error: \(err)\n".data(using: .utf8)!) }
        sem.signal()
    }
    if #available(macOS 14.0, *) {
        store.requestFullAccessToReminders(completion: handler)
    } else {
        store.requestAccess(to: .reminder, completion: handler)
    }
    sem.wait()
    return granted
}

// MARK: - 取得

func findList(_ name: String) -> EKCalendar {
    let cals = store.calendars(for: .reminder)
    guard let cal = cals.first(where: { $0.title == name }) else {
        die("リスト「\(name)」が見つからない。存在するのは: " + cals.map(\.title).joined(separator: ", "))
    }
    return cal
}

/// 未完了リマインダーを EventKit が返した「生の順序」のまま取得する。
func fetchRaw(_ cal: EKCalendar) -> [EKReminder] {
    let predicate = store.predicateForIncompleteReminders(
        withDueDateStarting: nil, ending: nil, calendars: [cal])
    let sem = DispatchSemaphore(value: 0)
    var out: [EKReminder] = []
    store.fetchReminders(matching: predicate) { reminders in
        out = reminders ?? []
        sem.signal()
    }
    sem.wait()
    return out
}

func byCreation(_ reminders: [EKReminder]) -> [EKReminder] {
    reminders.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
}

let stamp: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM/dd HH:mm:ss"
    return f
}()

func row(_ i: Int, _ r: EKReminder) -> String {
    let created = r.creationDate.map(stamp.string(from:)) ?? "-"
    let prio = String(format: "%d", r.priority)
    return "  \(String(format: "%2d", i))  prio=\(prio)  created=\(created)  \(r.title ?? "")"
}

// MARK: - コマンド

/// R4 の検証。生の fetch 順と作成日順を並べて出し、手動並び順と見比べる。
func cmdDump(_ listName: String) {
    let cal = findList(listName)
    let raw = fetchRaw(cal)
    guard !raw.isEmpty else { die("「\(listName)」に未完了のリマインダーが無い") }

    print("=== [A] EventKit が返した生の順序 (fetch順) ===")
    for (i, r) in raw.enumerated() { print(row(i + 1, r)) }

    let created = byCreation(raw)
    print("\n=== [B] 作成日の昇順 ===")
    for (i, r) in created.enumerated() { print(row(i + 1, r)) }

    let sameOrder = zip(raw, created).allSatisfy { $0.0.calendarItemIdentifier == $0.1.calendarItemIdentifier }
    print("\n[A] と [B] は\(sameOrder ? "同じ" : "違う")。")
    print("""

    ▼ここを目視で確認する
      iPhone/Mac の純正リマインダーで見えている「基本」の並びと、
      [A] または [B] が一致しているか。
        ・[A] が一致 → 手動並び順がそのまま取れている。案2すら不要（大当たり）
        ・[B] のみ一致 → 手動並べ替えをしていない状態。並べ替えてから再実行して再確認
        ・どちらも不一致 → 想定通り。案2（priority で順序を持つ）へ進む

    以降のコマンドの index は [B] 作成日順の番号を指す。
    """)
}

/// R1 の検証。先頭から順に priority 1,2,3... を書き込む。
func cmdSpread(_ listName: String) {
    let cal = findList(listName)
    let targets = byCreation(fetchRaw(cal))
    guard !targets.isEmpty else { die("「\(listName)」に未完了のリマインダーが無い") }

    print("作成日順に priority 1,2,3... を書き込む（priority は 1 が最優先、9 が最低）")
    for (i, r) in targets.enumerated() {
        let p = min(i + 1, 9)
        r.priority = p
        do {
            try store.save(r, commit: false)
            print("  set prio=\(p)  \(r.title ?? "")")
        } catch {
            print("  FAILED prio=\(p)  \(r.title ?? "")  -> \(error)")
        }
    }
    do { try store.commit() } catch { die("commit 失敗: \(error)") }

    // 保存した値が本当に戻ってくるか、EKEventStore を作り直して読み直す
    print("\n--- 別ストアで読み直し（ここで値が化けたら R1 が死んでいる）---")
    let verifyStore = EKEventStore()
    let sem = DispatchSemaphore(value: 0)
    if #available(macOS 14.0, *) {
        verifyStore.requestFullAccessToReminders { _, _ in sem.signal() }
    } else {
        verifyStore.requestAccess(to: .reminder) { _, _ in sem.signal() }
    }
    sem.wait()
    guard let vcal = verifyStore.calendars(for: .reminder).first(where: { $0.title == listName }) else { return }
    let p = verifyStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [vcal])
    let sem2 = DispatchSemaphore(value: 0)
    var reread: [EKReminder] = []
    verifyStore.fetchReminders(matching: p) { reread = $0 ?? []; sem2.signal() }
    sem2.wait()

    var mismatched = 0
    for (i, r) in byCreation(reread).enumerated() {
        let want = min(i + 1, 9)
        let ok = r.priority == want
        if !ok { mismatched += 1 }
        print("  \(ok ? "OK " : "NG ") 期待=\(want) 実際=\(r.priority)  \(r.title ?? "")")
    }
    print(mismatched == 0
          ? "\n=> R1 合格。1〜9 の中間値をそのまま保持できる。"
          : "\n=> R1 不合格。\(mismatched)件が別の値に丸められた。案2は3段階運用に縮小が必要。")
    print("""

    ▼次にやること（R2 / R3）
      1. iPhone の純正リマインダーで「基本」を開き、適当な1件のタイトルを編集して保存する
      2. さらに新規リマインダーを1件追加する
      3. Mac に戻って `swift ReminderProbe.swift dump 基本` を再実行
         → 編集した項目の priority が 1/5/9 に丸められていたら R2 不合格
         → 中間値のまま残っていれば R2 合格（＝案2が成立する）
      4. 同期の確認は 1〜3 を数分あけてから行う（R3）
    """)
}

/// 個別に priority を打つ。
func cmdSet(_ listName: String, _ indexArg: String, _ priorityArg: String) {
    guard let idx = Int(indexArg), let prio = Int(priorityArg), (0...9).contains(prio) else {
        die("使い方: set <リスト名> <index> <priority 0-9>")
    }
    let targets = byCreation(fetchRaw(findList(listName)))
    guard idx >= 1, idx <= targets.count else { die("index は 1〜\(targets.count)") }
    let r = targets[idx - 1]
    r.priority = prio
    do {
        try store.save(r, commit: true)
        print("set prio=\(prio)  \(r.title ?? "")")
    } catch { die("保存失敗: \(error)") }
}

/// 検証で汚した priority を全部 0 に戻す。
func cmdClear(_ listName: String) {
    let targets = fetchRaw(findList(listName))
    for r in targets where r.priority != 0 {
        r.priority = 0
        try? store.save(r, commit: false)
    }
    do { try store.commit(); print("「\(listName)」の priority を全て 0 に戻した。") }
    catch { die("commit 失敗: \(error)") }
}

/// おまけ。EKReminder に並び順を持つ非公開プロパティが生えていないか、
/// Objective-C ランタイムからプロパティ一覧を吸い出して確認する。
func cmdProbe(_ listName: String) {
    guard let sample = fetchRaw(findList(listName)).first else { die("リマインダーが1件も無い") }

    print("=== EKReminder のプロパティ一覧（非公開含む）===")
    var cls: AnyClass? = type(of: sample)
    let interesting = ["order", "sort", "index", "rank", "position", "display", "sequence"]
    var hits: [String] = []

    while let c = cls, c != NSObject.self {
        var count: UInt32 = 0
        if let props = class_copyPropertyList(c, &count) {
            var names: [String] = []
            for i in 0..<Int(count) {
                let name = String(cString: property_getName(props[i]))
                names.append(name)
                let lower = name.lowercased()
                if interesting.contains(where: { lower.contains($0) }) { hits.append(name) }
            }
            free(props)
            print("\n[\(NSStringFromClass(c))]")
            print("  " + names.sorted().joined(separator: ", "))
        }
        cls = class_getSuperclass(c)
    }

    guard !hits.isEmpty else {
        print("\n=> 並び順らしきプロパティは見つからなかった。案2で確定。")
        return
    }
    print("\n=== 順序っぽい名前の候補 ===")
    for key in Set(hits).sorted() {
        // 未知キーの value(forKey:) は NSException で即死するので、
        // セレクタに応答する場合だけ読む。
        if sample.responds(to: NSSelectorFromString(key)) {
            let v = sample.value(forKey: key)
            print("  \(key) = \(String(describing: v))")
        } else {
            print("  \(key) = (読み取り不可)")
        }
    }
    print("""

    ▼ここに値が出ていたら
      `dump` を並べ替え前後で実行し、この値が手動並び順と連動して変化するかを見る。
      連動していれば案1相当が iPhone アプリ単体で実現できる（非公開APIなので自分用限定）。
    """)
}

// MARK: - エントリポイント

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("""
    使い方:
      swift ReminderProbe.swift lists                     リスト一覧
      swift ReminderProbe.swift dump   <リスト名>          並び順の確認 (R4)
      swift ReminderProbe.swift spread <リスト名>          priority 1..9 を一括書き込み (R1)
      swift ReminderProbe.swift set    <リスト名> <i> <p>  個別に priority を設定
      swift ReminderProbe.swift clear  <リスト名>          priority を全て 0 に戻す
      swift ReminderProbe.swift probe  <リスト名>          非公開プロパティの調査
    """)
    exit(0)
}

guard requestAccess() else {
    die("リマインダーへのアクセスが許可されなかった。\nシステム設定 > プライバシーとセキュリティ > リマインダー でターミナルを許可する。")
}

switch command {
case "lists":
    for c in store.calendars(for: .reminder) { print("  \(c.title)") }
case "dump":
    guard args.count >= 2 else { die("使い方: dump <リスト名>") }
    cmdDump(args[1])
case "spread":
    guard args.count >= 2 else { die("使い方: spread <リスト名>") }
    cmdSpread(args[1])
case "set":
    guard args.count >= 4 else { die("使い方: set <リスト名> <index> <priority>") }
    cmdSet(args[1], args[2], args[3])
case "clear":
    guard args.count >= 2 else { die("使い方: clear <リスト名>") }
    cmdClear(args[1])
case "probe":
    guard args.count >= 2 else { die("使い方: probe <リスト名>") }
    cmdProbe(args[1])
default:
    die("不明なコマンド: \(command)")
}
