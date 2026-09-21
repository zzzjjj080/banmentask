#!/usr/bin/env python3
"""App Store Connect API を叩く道具。

PyJWT も cryptography も入っていない環境で動くよう、標準ライブラリと openssl だけで
ES256 の JWT を組む。openssl の出す署名は DER なので、JWT が要求する r||s の生形式へ直す。

使い方:
    ./Tools-ASC.py get  /v1/apps
    ./Tools-ASC.py post /v1/bundleIds '{"data": {...}}'
    ./Tools-ASC.py patch /v1/appStoreVersions/xxx '{"data": {...}}'

鍵はチーム全体のもの。アプリごとに作り直す必要はない。
"""
from __future__ import annotations
import base64
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

KEY_ID = "CH8R5RJGXQ"
ISSUER_ID = "cfeb84ca-47e6-45b2-8c5f-192212240b6c"
KEY_PATH = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{KEY_ID}.p8"
BASE = "https://api.appstoreconnect.apple.com"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """DER の SEQUENCE{INTEGER r, INTEGER s} を、32バイトずつの r||s に直す。"""
    if der[0] != 0x30:
        raise ValueError("DER の形式が違います")
    # 長さ表現が1バイトか複数バイトか
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("INTEGER が見つかりません")
        length = der[i + 1]
        value = der[i + 2 : i + 2 + length]
        i += 2 + length
        value = value.lstrip(b"\x00").rjust(32, b"\x00")
        out += value
    return out


def token() -> str:
    if not KEY_PATH.exists():
        sys.exit(f"APIキーがありません: {KEY_PATH}")
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    payload = {
        "iss": ISSUER_ID,
        "iat": int(time.time()) - 60,
        "exp": int(time.time()) + 60 * 15,   # 20分以内という決まり
        "aud": "appstoreconnect-v1",
    }
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    proc = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(KEY_PATH)],
        input=signing_input.encode(), capture_output=True,
    )
    if proc.returncode != 0:
        sys.exit(f"署名に失敗しました: {proc.stderr.decode()}")
    return f"{signing_input}.{b64url(der_to_raw(proc.stdout))}"


def call(method: str, path: str, body: str | None = None):
    url = path if path.startswith("http") else BASE + path
    data = body.encode() if body else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token()}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as res:
            raw = res.read()
            return res.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        # エラーは握り潰さない。Appleの返す理由がそのまま原因になる。
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, {"raw": raw.decode(errors="replace")}


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    method = sys.argv[1].upper()
    path = sys.argv[2]
    body = sys.argv[3] if len(sys.argv) > 3 else None
    status, payload = call(method, path, body)
    print(f"HTTP {status}")
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    sys.exit(0 if 200 <= status < 300 else 1)


if __name__ == "__main__":
    main()
