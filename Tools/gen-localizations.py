#!/usr/bin/env python3
"""訳（Localization/<言語>.json）から String Catalog を作る。

    python3 Tools/gen-localizations.py

作るもの（生成物はコミットする。ビルド時には作らない。引き継ぎ書 4-158）
- Shared/Localizable.xcstrings          画面の文言。4ターゲットとも Shared を含むので1つで足りる
- iOS/InfoPlist.xcstrings                ホーム画面の名前・リマインダーとカレンダーの許可文
- HomeWidget/InfoPlist.xcstrings         ウィジェットの名前・リマインダーの許可文
- Watch/InfoPlist.xcstrings              Watch アプリの名前
- WatchWidget/InfoPlist.xcstrings        文字盤の部品の名前
- iOS/AppShortcuts.xcstrings             Siri の言い回し

キーはコードに書いた日本語のまま。**元の言語は英語（en）にして、日本語も訳として明示的に持つ。**
元の言語を ja のままにすると、訳の無い言語（タイ語など）で日本語と英語が混ざる（引き継ぎ書 4-157）。

検算：全言語に全キーがあること、%@ / %lld の数と種類がキーと同じこと。食い違うと実行時に落ちる。
"""
import collections
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

langs = {}
for path in sorted(glob.glob("Localization/*.json")):
    t = json.load(open(path))
    langs[t["lang"]] = t
if "en" not in langs or "ja" not in langs:
    sys.exit("Localization/en.json と ja.json が要る")

keys = list(langs["ja"]["strings"].keys())


def placeholders(s):
    return collections.Counter(re.sub(r"%\d+\$", "%", m) for m in re.findall(r"%(?:\d+\$)?(?:lld|@|d)", s))


errors = []
for lang, t in langs.items():
    for k in keys:
        v = t["strings"].get(k)
        if v is None:
            errors.append(f"{lang}: キーが無い {k!r}")
        elif placeholders(k) != placeholders(v):
            errors.append(f"{lang}: %の数が違う {k!r} → {v!r}")
if errors:
    sys.exit("\n".join(errors))


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def catalog(entries):
    """entries: {キー: {言語: 値}}"""
    strings = collections.OrderedDict()
    for key in sorted(entries):
        strings[key] = {"extractionState": "manual",
                        "localizations": {l: unit(v) for l, v in sorted(entries[key].items())}}
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def write(path, data):
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"書いた: {path}（{len(data['strings'])} キー × {len(langs)} 言語）")


# 画面の文言
write("Shared/Localizable.xcstrings",
      catalog({k: {l: t["strings"][k] for l, t in langs.items()} for k in keys}))


def info(fields):
    """fields: {Info.plist のキー: 訳ファイルの infoplist の項目名}"""
    return catalog({plist_key: {l: t["infoplist"][src] for l, t in langs.items()}
                    for plist_key, src in fields.items()})


write("iOS/InfoPlist.xcstrings", info({
    "CFBundleDisplayName": "CFBundleDisplayName",
    "NSRemindersFullAccessUsageDescription": "NSRemindersFullAccessUsageDescription",
    "NSCalendarsFullAccessUsageDescription": "NSCalendarsFullAccessUsageDescription",
}))
write("HomeWidget/InfoPlist.xcstrings", info({
    "CFBundleDisplayName": "CFBundleDisplayName",
    "NSRemindersFullAccessUsageDescription": "WidgetRemindersUsage",
}))
write("Watch/InfoPlist.xcstrings", info({"CFBundleDisplayName": "CFBundleDisplayName"}))
write("WatchWidget/InfoPlist.xcstrings", info({"CFBundleDisplayName": "CFBundleDisplayName"}))

# Siri の言い回し。キーはコードの phrases に書いた日本語
write("iOS/AppShortcuts.xcstrings",
      catalog({"${applicationName}を更新": {l: t["shortcut_phrase"] for l, t in langs.items()}}))
