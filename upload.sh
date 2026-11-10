#!/bin/bash
# 盤面タスク（TaskFace）を App Store Connect に上げる。
#   ./upload.sh            project.yml の版・ビルド番号でアーカイブ → 書き出し → アップロード
# 署名鍵は interval-dist キーチェーンに入っている（引き継ぎ書 4-71）。
# **このリポジトリは公開なので、キーチェーンの合言葉はここに書かない。**
# ~/.appstoreconnect/interval-dist.pw（600）から読む。
set -eu
cd "$(dirname "$0")"

KEY=~/.appstoreconnect/private_keys/AuthKey_CH8R5RJGXQ.p8
KEY_ID=CH8R5RJGXQ
ISSUER=cfeb84ca-47e6-45b2-8c5f-192212240b6c

VER=$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*"\(.*\)".*/\1/')
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed 's/.*"\(.*\)".*/\1/')
WORK=/tmp/banmentask-archive
ARCHIVE="$WORK/BanmenTask-$VER-$BUILD.xcarchive"
echo "== $VER ($BUILD) を上げる"

which xcodegen >/dev/null && xcodegen generate >/dev/null

mkdir -p "$WORK"
rm -rf "$ARCHIVE" "$WORK/export"
echo "-- アーカイブ"
xcodebuild -project BanmenTask.xcodeproj -scheme BanmenTask -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -derivedDataPath "$WORK/dd" -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER" \
  archive > "$WORK/archive.log" 2>&1 || { grep -E 'error:' "$WORK/archive.log" | sort -u | head; exit 1; }
grep -q 'ARCHIVE SUCCEEDED' "$WORK/archive.log" || { tail -20 "$WORK/archive.log"; exit 1; }

echo "-- 書き出してアップロード"
security unlock-keychain -p "$(cat ~/.appstoreconnect/interval-dist.pw)" ~/Library/Keychains/interval-dist.keychain-db
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist Tools/ExportOptions.plist -exportPath "$WORK/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER" \
  > "$WORK/export.log" 2>&1 || { grep -E 'error' "$WORK/export.log" | sort -u | head; exit 1; }
grep -E 'EXPORT SUCCEEDED|Upload succeeded' "$WORK/export.log" | sort -u

echo "== 上がった。処理が終わるまで数分かかる → python3 Tools/asc-submit.py $VER $BUILD"
rm -rf "$WORK/dd"
