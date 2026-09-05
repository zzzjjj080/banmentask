# 盤面タスク

Apple Watch の文字盤に、リマインダーの上位2件を常時表示するコンプリケーション。

```
┌──────────────────┐
│  iPhone返送       │  ← 1件目・太字
│  バットテープ巻く  │  ← 2件目・グレー
└──────────────────┘
```

| Bundle ID | 用途 |
|---|---|
| `com.zzzjjj080.banmentask` | iOS 本体。データ取得と Watch への送信 |
| `com.zzzjjj080.banmentask.watchkitapp` | Watch アプリ。受信して App Group に保存 |
| `com.zzzjjj080.banmentask.watchkitapp.widget` | ウィジェット拡張。文字盤の描画 |
| `group.com.zzzjjj080.banmentask` | App Group。Watch アプリ ⇄ ウィジェット拡張のデータ共有 |

## いまの段階：v2（EventKit 取り込み + 並べ替え → priority 保存）

iPhone アプリが EventKit から対象リストの未完了リマインダーを読み、
上位2件を Watch へ送る。アプリ内でドラッグ並べ替えすると、その順序が
`priority`(1〜9) としてリマインダー本体に保存される。

```
純正リマインダー ──EventKit──▶ iPhone アプリ ──WatchConnectivity──▶ Watch アプリ ──App Group──▶ ウィジェット ──▶ 文字盤
      ▲                          │ ドラッグ並べ替え                      └─ WidgetCenter.reloadAllTimelines()
      └──── priority 1〜9 を保存 ─┘
```

**並び順のルール**

- priority 1〜9 の項目を昇順で先頭に、0（未設定）は作成日順で後ろ
- 純正アプリで新規追加 → priority 0 → 自動的に末尾へ
- 自作アプリでドラッグ → 先頭から 1,2,3… を書き込み。10件目以降は 0 に戻す
- 純正アプリ側では「!!!」「!!」「!」として見える（1〜4 / 5 / 6〜9）

**更新のタイミング（v2 時点）**

- アプリを開いた時（`scenePhase == .active`）
- アプリが前面にいる間に純正側で変更があった時（`EKEventStoreChanged`）
- 上位2件が変わった時だけ Watch へ送る。1日50回の転送枠を守るため

アプリを閉じている間の変更は、次に開くまで文字盤に反映されない。裏更新は v3。

## セットアップ

### 0. App Group を先に登録する（1回だけ）

https://developer.apple.com/account/resources/identifiers/list/applicationGroup で
`group.com.zzzjjj080.banmentask` を作る。

**後回しにするとウィジェットが App Group を読めず「なぜか空欄」で時間が溶ける。** 必ず先にやる。

Bundle ID 3つは Automatic signing に任せれば Xcode が勝手に作る。

### 1. Team ID を入れる

`project.yml` の `DEVELOPMENT_TEAM: XXXXXXXXXX` を自分の Team ID に置き換える。
developer.apple.com/account → Membership details に載っている10桁。

### 2. プロジェクトを生成して開く

```sh
brew install xcodegen      # 初回のみ
cd BanmenTask
xcodegen generate
open BanmenTask.xcodeproj
```

`project.yml` を編集したら `xcodegen generate` を再実行するだけ。`.xcodeproj` は追跡しない。

#### xcodegen を使いたくない場合

Xcode で File → New → Project → **watchOS → App** を選び、
「Watch-only App」の**チェックを外して** iOS companion 付きで作る。
その後 File → New → Target → **watchOS → Widget Extension** を追加。
Bundle ID を上の表の通りに揃え、3ターゲットに App Group を付け、
`Shared/` `iOS/` `Watch/` `WatchWidget/` のファイルを各ターゲットに放り込む。
`Shared/` は3ターゲット全部に Target Membership を付けること。

### 3. 実機で動かす

1. iPhone を Mac に繋ぎ、スキーム **BanmenTask** で iPhone に Run
2. iPhone の Watch アプリ →「盤面タスク」が出たら Watch にインストール
   （出ない場合は Watch アプリ → 一般 → 「Show app on Apple Watch」）
3. Watch で文字盤を長押し → 編集 → コンプリケーション → 横長スロットに「盤面タスク」を置く
   - 対応文字盤：モジュラー / モジュラーコンパクト / インフォグラフ モジュラー
4. iPhone の盤面タスクで2行を入力して「Watch に送信」
5. 数秒〜数十秒で文字盤が変わる

### 4. 開発中の必須設定

iPhone の 設定 → デベロッパ → **Widget Developer Mode を ON**。

これを忘れると `transferCurrentComplicationUserInfo` の **1日50回制限**に引っかかり、
「更新されない」で半日溶かす。本番運用時は OFF に戻す（電池のため）。

## v0 の合格条件

- [ ] iPhone の状態欄で「ペアリング / Watch アプリ / 文字盤に配置済み」が全部 ✓
- [ ] 送信後に文字盤の表示が変わる
- [ ] Watch アプリを一度も開かずに送っても変わる（裏起動が効いている）
- [ ] Watch を再起動しても表示が残る（App Group に保存されている）

## ロードマップ

| 版 | 内容 | 状態 |
|---|---|---|
| v0 | 手打ち2行を文字盤に出す。配管の疎通 | 実装済み（実機未確認） |
| v1 | EventKit から対象リストの先頭2件を取得して送る | 実装済み（実機未確認） |
| v2 | 並び順を `priority`(1〜9) に焼く。ドラッグ並べ替え UI。リスト切替 | 実装済み（実機未確認） |
| v3 | BGAppRefreshTask で裏更新。Watch から完了操作 | 未着手 |

**検証の状態**（`../experiments/watch-complication/`）

| # | 内容 | 結果 |
|---|---|---|
| R1 | 中間値 (2 など) を保存・再読込できるか | **合格**（2026-09-05） |
| R2 | 純正アプリで編集した時に丸められないか | 未検証。不合格でも「編集した項目だけ順位が飛ぶ」程度の影響 |
| R3 | iCloud 同期後も保たれるか | 未検証 |
| R4 | 生の fetch 順が手動並び順と一致するか | 未確定（並べ替え前後で差が出ず） |

## 設計メモ

- **並び順は EventKit から取れない**（純正の手動並べ替えは API 非公開）。
  v2 で `priority` を順位の保存場所に流用する。検証ツールは `../experiments/watch-complication/`。
- ウィジェット拡張から直接 EventKit を叩かない。watchOS のウィジェット拡張は
  本体が許可済みでも `.denied` を返す既知の挙動があるため、iPhone 側で取得して Watch へ送る。
- 転送は `updateApplicationContext`（最新状態の保持）と `transferCurrentComplicationUserInfo`
  （裏起動して即時反映）の2経路。後者は1日50回まで。
