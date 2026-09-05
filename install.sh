#!/bin/bash
# 盤面タスクを iPhone と Apple Watch に入れる。Xcode を開かなくていい。
#
#   ./install.sh          生成 → ビルド → iPhone と Watch の両方に入れる
#   ./install.sh phone    iPhone だけ
#   ./install.sh watch    Watch だけ
#
# 前提: iPhone と Watch が Mac と同じ Wi-Fi にいてロック解除済み（USB でも可）。
set -e
cd "$(dirname "$0")"
WHAT="${1:-both}"
DD=/tmp/banmentask-build

echo "→ プロジェクト生成"
xcodegen generate --quiet

LIST=$(xcrun devicectl list devices 2>/dev/null || true)
uuid() { echo "$LIST" | grep -E "$1" | grep -E 'connected|available' \
         | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1 || true; }
PHONE=$(uuid 'iPhone')
WATCH=$(uuid 'Apple Watch')

build() {  # build <scheme> <platform>
  xcodebuild -project BanmenTask.xcodeproj -scheme "$1" -configuration Debug \
    -destination "generic/platform=$2" -derivedDataPath "$DD" \
    -allowProvisioningUpdates build 2>&1 | grep -E 'error:|warning: .*Swift|BUILD (SUCCEEDED|FAILED)' || true
}

if [ "$WHAT" = both ] || [ "$WHAT" = phone ]; then
  [ -n "$PHONE" ] || { echo "❌ iPhone が見つかりません"; echo "$LIST" | tail -n +3; exit 1; }
  echo "→ iPhone 用ビルド"
  build BanmenTask iOS
  APP="$DD/Build/Products/Debug-iphoneos/BanmenTask.app"
  [ -d "$APP" ] || { echo "❌ iPhone 用ビルド失敗。上のエラーを貼ってください"; exit 1; }
  echo "→ iPhone にインストール"
  xcrun devicectl device install app --device "$PHONE" "$APP" 2>&1 | grep -E 'bundleID|error' || true
  echo "✅ iPhone OK"
fi

if [ "$WHAT" = both ] || [ "$WHAT" = watch ]; then
  [ -n "$WATCH" ] || { echo "❌ Apple Watch が見つかりません（iPhone 経由で見えている必要があります）"; echo "$LIST" | tail -n +3; exit 1; }
  echo "→ Watch 用ビルド"
  build BanmenTaskWatch watchOS
  APP="$DD/Build/Products/Debug-watchos/BanmenTaskWatch.app"
  [ -d "$APP" ] || { echo "❌ Watch 用ビルド失敗。上のエラーを貼ってください"; exit 1; }
  echo "→ Watch にインストール（1〜2分かかることがあります）"
  xcrun devicectl device install app --device "$WATCH" "$APP" 2>&1 | grep -E 'bundleID|error' || true
  echo "✅ Watch OK"
fi

echo
echo "Watch アプリの右下に BuildInfo.marker（現在: $(grep -o 'marker = "[^"]*"' Shared/TaskStore.swift | cut -d'"' -f2)）が出ていれば入れ替わっています。"
