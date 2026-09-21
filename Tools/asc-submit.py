#!/usr/bin/env python3
"""版にビルドを紐づけて審査に出す。課金の未審査の説明も一緒に出す。

    python3 Tools/asc-submit.py 1.2 6

提出と公開はいちいち確認を取らない決まり（指示書）。公開は承認後に自動（AFTER_APPROVAL）。
足りないものがあると、提出の項目を作る所で Apple が理由をまとめて返す（引き継ぎ書 4-49）。
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402

APP = "6809464254"
IAP = "6809464583"


def call(method, path, body=None, ok_codes=()):
    status, data = asc.call(method, path, json.dumps(body) if body is not None else None)
    if not 200 <= status < 300 and status not in ok_codes:
        raise SystemExit(f"{method} {path} → HTTP {status}\n{json.dumps(data, ensure_ascii=False, indent=1)[:2500]}")
    return status, data


def main(vs, build_no):
    _, d = call("GET", f"/v1/apps/{APP}/appStoreVersions?limit=20")
    v = next(x for x in d["data"] if x["attributes"]["versionString"] == vs)
    print("版", vs, v["attributes"]["appStoreState"], v["id"])

    _, d = call("GET", f"/v1/builds?filter[app]={APP}&filter[version]={build_no}&filter[preReleaseVersion.version]={vs}")
    if not d["data"]:
        raise SystemExit(f"ビルド {vs} ({build_no}) がまだ無い（処理中）")
    b = d["data"][0]
    if b["attributes"]["processingState"] != "VALID":
        raise SystemExit(f"ビルドが {b['attributes']['processingState']}")
    call("PATCH", f"/v1/appStoreVersions/{v['id']}/relationships/build",
         {"data": {"type": "builds", "id": b["id"]}})
    print("ビルドを紐づけた:", build_no)

    # 提出の枠。すでに開いている枠があれば使う
    _, d = call("GET", f"/v1/reviewSubmissions?filter[app]={APP}&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES")
    if d["data"]:
        sub = d["data"][0]["id"]
        print("既存の提出枠を使う:", sub)
    else:
        _, d = call("POST", "/v1/reviewSubmissions", {"data": {
            "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
            "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
        sub = d["data"]["id"]
        print("提出枠を作った:", sub)

    status, d = call("POST", "/v1/reviewSubmissionItems", {"data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}}, ok_codes=(409,))
    if status == 409:
        print("版はすでに枠に入っている:", json.dumps(d, ensure_ascii=False)[:300])
    else:
        print("版を枠に入れた")

    call("PATCH", f"/v1/reviewSubmissions/{sub}", {"data": {
        "type": "reviewSubmissions", "id": sub, "attributes": {"submitted": True}}})
    print("審査に出した")

    # 課金の説明（新しく足した言語）の審査。承認済みの課金なので、版と別に出せる
    status, d = call("POST", "/v1/inAppPurchaseSubmissions", {"data": {
        "type": "inAppPurchaseSubmissions",
        "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": IAP}}}}}, ok_codes=(409,))
    print("課金の説明を審査に出した" if status < 300 else "課金の提出は不要または不可: " + json.dumps(d, ensure_ascii=False)[:400])

    _, d = call("GET", f"/v1/appStoreVersions/{v['id']}")
    print("版の状態:", d["data"]["attributes"]["appStoreState"])


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(sys.argv[1], sys.argv[2])
