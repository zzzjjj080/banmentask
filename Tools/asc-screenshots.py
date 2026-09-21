#!/usr/bin/env python3
"""掲載用スクリーンショットを、日本語以外の全言語へ入れる。

    python3 Tools/asc-screenshots.py 1.2 <フォルダ>

<フォルダ>/phone/*.png → iPhone 6.7インチ枠（APP_IPHONE_67、1320×2868）
<フォルダ>/watch/*.png → Apple Watch 枠（APP_WATCH_SERIES_10、416×496）

日本語（ja）は触らない（前の版の日本語の画像がそのまま引き継がれている）。
枠に既にある画像は消してから入れる。何度流しても同じ結果になる。

上げ方は3段階（引き継ぎ書 4-102）：
  POST /v1/appScreenshots（名前と大きさで予約）→ uploadOperations の通りに PUT → PATCH uploaded=true と md5
"""
import glob
import hashlib
import json
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402

APP = "6809464254"
SETS = {"phone": "APP_IPHONE_67", "watch": "APP_WATCH_SERIES_10"}


def call(method, path, body=None):
    status, data = asc.call(method, path, json.dumps(body) if body is not None else None)
    if not 200 <= status < 300:
        raise SystemExit(f"{method} {path} → HTTP {status}\n{json.dumps(data, ensure_ascii=False)[:1200]}")
    return data


def get_all(path):
    out = []
    while path:
        d = call("GET", path)
        out += d["data"]
        path = d.get("links", {}).get("next")
    return out


def upload(set_id, path):
    raw = open(path, "rb").read()
    d = call("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(raw)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
    for op in d["attributes"]["uploadOperations"]:
        chunk = raw[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req).read()
    call("PATCH", f"/v1/appScreenshots/{d['id']}", {"data": {
        "type": "appScreenshots", "id": d["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(raw).hexdigest()}}})
    return d["id"]


def main(vs, folder):
    versions = [v for v in get_all(f"/v1/apps/{APP}/appStoreVersions?limit=20")
                if v["attributes"]["versionString"] == vs]
    if not versions:
        raise SystemExit(f"{vs} が無い")
    v = versions[0]
    files = {k: sorted(glob.glob(os.path.join(folder, k, "*.png"))) for k in SETS}
    for k, fs in files.items():
        if not fs:
            raise SystemExit(f"{folder}/{k} に画像が無い")
    locs = get_all(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations?limit=50")
    for loc in locs:
        locale = loc["attributes"]["locale"]
        if locale == "ja":
            continue
        have = {s["attributes"]["screenshotDisplayType"]: s["id"]
                for s in get_all(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")}
        for kind, display in SETS.items():
            set_id = have.get(display)
            if set_id:
                for old in get_all(f"/v1/appScreenshotSets/{set_id}/appScreenshots"):
                    call("DELETE", f"/v1/appScreenshots/{old['id']}")
            else:
                set_id = call("POST", "/v1/appScreenshotSets", {"data": {
                    "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display},
                    "relationships": {"appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]["id"]
            for f in files[kind]:
                upload(set_id, f)
        print(f"{locale}: iPhone {len(files['phone'])} 枚・Watch {len(files['watch'])} 枚")

    # Apple 側の処理（画像の検査）が終わるのを待って、壊れたものが無いか確かめる
    time.sleep(20)
    bad = 0
    for loc in locs:
        if loc["attributes"]["locale"] == "ja":
            continue
        for s in get_all(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets"):
            for shot in get_all(f"/v1/appScreenshotSets/{s['id']}/appScreenshots"):
                state = (shot["attributes"].get("assetDeliveryState") or {}).get("state")
                if state not in ("COMPLETE", "UPLOAD_COMPLETE"):
                    bad += 1
                    print("  処理中/失敗:", loc["attributes"]["locale"], shot["attributes"]["fileName"], state)
    print("すべて処理済み" if not bad else f"{bad} 枚がまだ処理中か失敗")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
