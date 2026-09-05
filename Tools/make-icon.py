#!/usr/bin/env python3
"""アプリアイコンを生成する。黒背景に、文字盤のコンプリケーションと同じ「2行のタスク」。

  python3 Tools/make-icon.py            text 版（既定。文字盤の見た目そのまま）
  python3 Tools/make-icon.py bars       bars 版（円＋バー。小さくても崩れない）

出力先: iOS/Assets.xcassets と Watch/Assets.xcassets の AppIcon（1024x1024）
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 1024
WHITE = (255, 255, 255)
GRAY = (150, 150, 155)
BLACK = (0, 0, 0)
FONT = "/usr/share/fonts/opentype/ipafont-gothic/ipagp.ttf"

def circle(d, cx, cy, r, color, width):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=width)

def bar(d, x, y, w, h, color):
    d.rounded_rectangle([x, y, x + w, y + h], radius=h // 2, fill=color)

def render(variant):
    img = Image.new("RGB", (SIZE, SIZE), BLACK)
    d = ImageDraw.Draw(img)
    # watchOS は円マスクなので、中央 70% に収める
    left, right = 190, 850
    rows = [(360, WHITE, 1.0), (640, GRAY, 0.78)]   # (中心y, 色, 2行目の縮小率)
    for cy, color, scale in rows:
        r = int(62 * scale)
        circle(d, left + 62, cy, r, color, int(20 * scale))
        x0 = left + 62 + r + 60
        if variant == "text":
            label = "牛乳を買う" if color == WHITE else "電話する"
            # 右端に収まるまで縮める
            size = int(150 * scale)
            while size > 40:
                font = ImageFont.truetype(FONT, size)
                if d.textlength(label, font=font) <= right - x0: break
                size -= 4
            d.text((x0, cy), label, font=font, fill=color, anchor="lm",
                   stroke_width=max(2, size // 25), stroke_fill=color)
        else:
            h = int(92 * scale)
            w = int((right - x0) * (1.0 if color == WHITE else 0.72))
            bar(d, x0, cy - h // 2, w, h, color)
    return img

def write_asset(img, xcassets_dir, platform):
    appicon = os.path.join(xcassets_dir, "AppIcon.appiconset")
    os.makedirs(appicon, exist_ok=True)
    img.save(os.path.join(appicon, "icon.png"))
    json.dump({"images": [{"filename": "icon.png", "idiom": "universal",
                           "platform": platform, "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}},
              open(os.path.join(appicon, "Contents.json"), "w"), indent=2)
    json.dump({"info": {"author": "xcode", "version": 1}},
              open(os.path.join(xcassets_dir, "Contents.json"), "w"), indent=2)

if __name__ == "__main__":
    variant = sys.argv[1] if len(sys.argv) > 1 else "text"
    img = render(variant)
    write_asset(img, os.path.join(ROOT, "iOS", "Assets.xcassets"), "ios")
    write_asset(img, os.path.join(ROOT, "Watch", "Assets.xcassets"), "watchos")
    img.save(os.path.join(ROOT, "Tools", f"icon-preview-{variant}.png"))
    print(f"icon ({variant}) written")
