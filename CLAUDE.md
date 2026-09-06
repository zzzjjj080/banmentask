# 盤面タスク — Claude 向けメモ

## ビルドの印（必ず守る）

コードを push するたびに `Shared/TaskStore.swift` の `BuildInfo.marker` を1つ進める（b10 → b11）。
仁がスマホ側で印を見て、Claude 側と一致しているかを確認しながら進めるため。

- 表示は目立たせない。画面の右上に 8〜9pt の極小・薄いグレー
- iPhone と Watch の両方の画面に出す（片方だけ入れ替わらない事故を見抜く）
- 返信で「印は b11」と必ず伝える

## 入れ方

`./install.sh` で xcodegen → xcodebuild → devicectl まで通る。Xcode を開く必要はない。
`project.yml` を変えた時も同じコマンドでよい（毎回生成し直す）。

## 設計の要点

- データは純正リマインダー（EventKit）。自前 DB は持たない
- 並び順は `priority`(1〜9)。純正の手動並び順は API で取れない（検証済み: `../experiments/watch-complication/`）
- iPhone → Watch は WatchConnectivity。`transferCurrentComplicationUserInfo` は1日50回まで。上位2件が変わった時だけ送る
- 裏起動直後は WCSession の activate 完了を待ってから送る（`PhoneSession.ensureActivated`）
- Watch 側は `ExtensionDelegate.applicationDidFinishLaunching` で WCSession を立てる
- 文字盤の2行は1つの Text に改行で繋ぎ、同じ倍率で縮める。iPhone のプレビュー（`WatchMockView`）も同じルール
