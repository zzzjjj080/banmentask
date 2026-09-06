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

# 端末の特定は JSON で行う。テキスト出力の grep は列ズレで別の ID を拾うことがある。
DEVJSON=/tmp/banmentask-devices.json
xcrun devicectl list devices --json-output "$DEVJSON" >/dev/null 2>&1 || true
pick() {  # pick <platform>  → identifier（接続中を優先）
  python3 - "$1" "$DEVJSON" <<'PY2'
import json, sys
platform, path = sys.argv[1], sys.argv[2]
try:
    devices = json.load(open(path))["result"]["devices"]
except Exception:
    sys.exit(0)
cands = [d for d in devices if d.get("hardwareProperties", {}).get("platform") == platform]
cands.sort(key=lambda d: d.get("connectionProperties", {}).get("tunnelState") != "connected")
if cands:
    print(cands[0]["identifier"])
PY2
}
PHONE=$(pick iOS)
WATCH=$(pick watchOS)
LIST=$(xcrun devicectl list devices 2>/dev/null || true)

install_to() {  # install_to <identifier> <app path>
  local out
  if out=$(xcrun devicectl device install app --device "$1" "$2" 2>&1); then
    echo "$out" | grep -E 'bundleID' || true
    return 0
  fi
  echo "$out" | tail -5
  return 1
}

build() {  # build <scheme> <platform>  失敗したら 1 を返す
  local log="$DD/$1.log"
  mkdir -p "$DD"
  if xcodebuild -project BanmenTask.xcodeproj -scheme "$1" -configuration Debug \
      -destination "generic/platform=$2" -derivedDataPath "$DD" \
      -allowProvisioningUpdates build >"$log" 2>&1; then
    grep -E 'BUILD SUCCEEDED' "$log" || true
    return 0
  fi
  grep -E 'error:|BUILD FAILED' "$log" | sort -u
  return 1
}

if [ "$WHAT" = both ] || [ "$WHAT" = phone ]; then
  [ -n "$PHONE" ] || { echo "❌ iPhone が見つかりません"; echo "$LIST" | tail -n +3; exit 1; }
  echo "→ iPhone 用ビルド"
  rm -rf "$DD/Build/Products/Debug-iphoneos/BanmenTask.app"   # 古いビルドを入れないため
  build BanmenTask iOS || { echo "❌ iPhone 用ビルド失敗。上のエラーを貼ってください"; exit 1; }
  APP="$DD/Build/Products/Debug-iphoneos/BanmenTask.app"
  echo "→ iPhone にインストール"
  install_to "$PHONE" "$APP" || { echo "❌ iPhone へのインストール失敗"; exit 1; }
  echo "✅ iPhone OK"
fi

if [ "$WHAT" = both ] || [ "$WHAT" = watch ]; then
  [ -n "$WATCH" ] || { echo "❌ Apple Watch が見つかりません（iPhone 経由で見えている必要があります）"; echo "$LIST" | tail -n +3; exit 1; }
  echo "→ Watch 用ビルド"
  rm -rf "$DD/Build/Products/Debug-watchos/BanmenTaskWatch.app"
  build BanmenTaskWatch watchOS || { echo "❌ Watch 用ビルド失敗。上のエラーを貼ってください"; exit 1; }
  APP="$DD/Build/Products/Debug-watchos/BanmenTaskWatch.app"
  echo "→ Watch にインストール（1〜2分かかることがあります）"
  install_to "$WATCH" "$APP" || { echo "❌ Watch へのインストール失敗"; exit 1; }
  echo "✅ Watch OK"
fi

echo
echo "Watch アプリの右下に BuildInfo.marker（現在: $(grep -o 'marker = "[^"]*"' Shared/TaskStore.swift | cut -d'"' -f2)）が出ていれば入れ替わっています。"
