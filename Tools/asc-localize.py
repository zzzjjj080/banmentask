#!/usr/bin/env python3
"""盤面タスク（TaskFace）の掲載情報を、訳（Localization/<言語>.json）から App Store Connect に入れる。

    python3 Tools/asc-localize.py status
    python3 Tools/asc-localize.py version 1.2      版を作る（無ければ）。公開は承認後に自動
    python3 Tools/asc-localize.py listing 1.2      名前・サブタイトル・説明・キーワード・宣伝文・更新内容・URL
    python3 Tools/asc-localize.py iap              課金の説明（各言語）と販売地域（全地域）
    python3 Tools/asc-localize.py primary          元の言語を en-US に（英語のスクショを上げてから）
    python3 Tools/asc-localize.py territories      アプリの配信国を全地域へ

**配信国を広げるのは、各言語の掲載を持つ版が公開されてから**（引き継ぎ書 4-88b）。
先に広げると、いま公開中の日本語だけの版が全世界に出る。
課金の販売地域は先に広げてよい。日本だけだと米国の審査用アカウントで買えず 2.1(b) で落ちる（4-153）。
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402  Tools/asc.py（標準ライブラリと openssl だけで JWT を作る）

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = "6809464254"
IAP = "6809464583"
SITE = "https://zzzjjj080.github.io/banmentask/"

# 訳ファイルの言語 → ストアの言語。同じ文で地域違いのストアにも出す（見つかりやすくなる）
LOCALES = {
    "en": ["en-US", "en-GB", "en-AU", "en-CA"],
    "ja": ["ja"],
    "zh-Hans": ["zh-Hans"], "zh-Hant": ["zh-Hant"], "ko": ["ko"],
    "es": ["es-ES", "es-MX"], "fr": ["fr-FR", "fr-CA"], "de": ["de-DE"], "it": ["it"],
    "pt-BR": ["pt-BR"], "ru": ["ru"], "ar": ["ar-SA"],
    "nl": ["nl-NL"], "sv": ["sv"], "tr": ["tr"], "id": ["id"],
}


def load(lang):
    return json.load(open(os.path.join(ROOT, "Localization", f"{lang}.json")))


def urls(lang):
    base = SITE if lang == "ja" else SITE + "en/"
    return base, base + "privacy.html"


def call(method, path, body=None):
    status, data = asc.call(method, path, json.dumps(body) if body is not None else None)
    if not 200 <= status < 300:
        errs = (data or {}).get("errors", [data])
        raise SystemExit(f"{method} {path} → HTTP {status}\n" + json.dumps(errs, ensure_ascii=False, indent=1)[:1500])
    return data


def get_all(path):
    out = []
    while path:
        d = call("GET", path)
        out += d["data"]
        path = d.get("links", {}).get("next")
    return out


def version_of(vs):
    for v in get_all(f"/v1/apps/{APP}/appStoreVersions?limit=20"):
        if v["attributes"]["versionString"] == vs and v["attributes"]["platform"] == "IOS":
            return v
    return None


def editable_app_info():
    infos = get_all(f"/v1/apps/{APP}/appInfos")
    for i in infos:
        state = i["attributes"].get("state") or i["attributes"].get("appStoreState")
        if state not in ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE"):
            return i
    raise SystemExit("編集できる appInfo が無い。先に次の版を作る（引き継ぎ書 4-88）")


def cmd_status():
    a = call("GET", f"/v1/apps/{APP}")["data"]["attributes"]
    print("名前:", a["name"], "| 元の言語:", a["primaryLocale"])
    for v in get_all(f"/v1/apps/{APP}/appStoreVersions?limit=5"):
        x = v["attributes"]
        print("版", x["versionString"], x["appStoreState"], x["releaseType"], v["id"])
    for i in get_all(f"/v1/apps/{APP}/appInfos"):
        locs = get_all(f"/v1/appInfos/{i['id']}/appInfoLocalizations")
        print("appInfo", i["id"], i["attributes"].get("state"), "| 掲載言語", len(locs), sorted(l["attributes"]["locale"] for l in locs))
    iap = call("GET", f"/v2/inAppPurchases/{IAP}")["data"]["attributes"]
    print("課金:", iap["name"], iap["state"])


def cmd_version(vs):
    v = version_of(vs)
    if v:
        print(f"{vs} はある:", v["attributes"]["appStoreState"], v["id"])
        return
    d = call("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": vs, "releaseType": "AFTER_APPROVAL",
                       "copyright": "2026 Jin Nakamura"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
    print(f"{vs} を作った:", d["data"]["id"])


def cmd_listing(vs):
    v = version_of(vs)
    if not v:
        raise SystemExit(f"{vs} が無い。先に version {vs}")
    info = editable_app_info()
    have_info = {l["attributes"]["locale"]: l["id"] for l in get_all(f"/v1/appInfos/{info['id']}/appInfoLocalizations")}

    # 1) 名前・サブタイトル・ポリシーURL（appInfoLocalizations）
    for lang, locales in LOCALES.items():
        t = load(lang)["store"]
        support, privacy = urls(lang)
        for loc in locales:
            attrs = {"name": t["name"], "subtitle": t["subtitle"], "privacyPolicyUrl": privacy}
            if loc in have_info:
                call("PATCH", f"/v1/appInfoLocalizations/{have_info[loc]}",
                     {"data": {"type": "appInfoLocalizations", "id": have_info[loc], "attributes": attrs}})
                print("名前を更新:", loc, t["name"])
            else:
                call("POST", "/v1/appInfoLocalizations", {"data": {
                    "type": "appInfoLocalizations", "attributes": {"locale": loc, **attrs},
                    "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
                print("名前を追加:", loc, t["name"])

    # 2) 説明・キーワード・宣伝文・更新内容・サポートURL（appStoreVersionLocalizations）
    #    appInfoLocalizations を作ると自動で生えることがあるので、作る前に読み直す
    have_ver = {l["attributes"]["locale"]: l["id"]
                for l in get_all(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")}
    for lang, locales in LOCALES.items():
        t = load(lang)["store"]
        support, _ = urls(lang)
        attrs = {"description": t["description"], "keywords": t["keywords"],
                 "promotionalText": t["promo"], "whatsNew": t["whatsNew"], "supportUrl": support}
        for loc in locales:
            if loc in have_ver:
                call("PATCH", f"/v1/appStoreVersionLocalizations/{have_ver[loc]}",
                     {"data": {"type": "appStoreVersionLocalizations", "id": have_ver[loc], "attributes": attrs}})
                print("説明を更新:", loc)
            else:
                call("POST", "/v1/appStoreVersionLocalizations", {"data": {
                    "type": "appStoreVersionLocalizations", "attributes": {"locale": loc, **attrs},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
                print("説明を追加:", loc)


def cmd_primary():
    """元の言語を英語へ。訳の無い国のストアが日本語で出ないように（引き継ぎ書 4-157）。
    - appInfos ではなく apps の属性（appInfos に送ると 409 unknown attribute）
    - **先に en-US のスクリーンショットが要る**（無いと 409 MISSING_SCREENSHOTS_PRIMARY_LOCALE）"""
    call("PATCH", f"/v1/apps/{APP}",
         {"data": {"type": "apps", "id": APP, "attributes": {"primaryLocale": "en-US"}}})
    print("元の言語を en-US にした")


def all_territories():
    return [t["id"] for t in get_all("/v1/territories?limit=200")]


def cmd_iap():
    have = {l["attributes"]["locale"]: l["id"]
            for l in get_all(f"/v2/inAppPurchases/{IAP}/inAppPurchaseLocalizations")}
    for lang, locales in LOCALES.items():
        t = load(lang)["iap"]
        for loc in locales:
            if loc in have:
                continue   # 既にある言語（日本語）は触らない。書き換えると課金の審査がやり直しになりうる
            call("POST", "/v1/inAppPurchaseLocalizations", {"data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {"locale": loc, "name": t["name"], "description": t["description"]},
                "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": IAP}}}}})
            print("課金の説明を追加:", loc, t["name"])

    # 販売地域：消してから全地域で作り直す（UPDATE は無い。承認済みのままでできる。4-88b）
    terr = all_territories()
    cur = call("GET", f"/v2/inAppPurchases/{IAP}/inAppPurchaseAvailability")
    cur_id = (cur.get("data") or {}).get("id")
    if cur_id:
        n = len(get_all(f"/v1/inAppPurchaseAvailabilities/{cur_id}/availableTerritories?limit=200"))
        if n >= len(terr):
            print(f"課金の販売地域はすでに全地域（{n}）")
            return
        print(f"課金の販売地域はいま {n} 地域。作り直す")
    # DELETE は 403（許されるのは CREATE と GET_INSTANCE だけ。2026-09-21 実測）。作るだけで置き換わる
    call("POST", "/v1/inAppPurchaseAvailabilities", {"data": {
        "type": "inAppPurchaseAvailabilities", "attributes": {"availableInNewTerritories": True},
        "relationships": {
            "inAppPurchase": {"data": {"type": "inAppPurchases", "id": IAP}},
            "availableTerritories": {"data": [{"type": "territories", "id": x} for x in terr]}}}})
    print(f"課金の販売地域を全 {len(terr)} 地域にした")


def cmd_territories():
    av = call("GET", f"/v1/apps/{APP}/appAvailabilityV2")["data"]
    items = get_all(f"/v2/appAvailabilities/{av['id']}/territoryAvailabilities?limit=200")
    off = [i for i in items if not i["attributes"]["available"]]
    print(f"配信中 {len(items) - len(off)} / {len(items)}。これから {len(off)} か国を足す")
    for n, i in enumerate(off, 1):
        call("PATCH", f"/v1/territoryAvailabilities/{i['id']}",
             {"data": {"type": "territoryAvailabilities", "id": i["id"], "attributes": {"available": True}}})
        if n % 25 == 0:
            print(f"  {n} / {len(off)}")
    print("全地域で配信にした。availableInNewTerritories:", av["attributes"].get("availableInNewTerritories"))


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    {"status": lambda: cmd_status(),
     "version": lambda: cmd_version(args[1]),
     "listing": lambda: cmd_listing(args[1]),
     "iap": lambda: cmd_iap(),
     "primary": lambda: cmd_primary(),
     "territories": lambda: cmd_territories()}[args[0]]()
