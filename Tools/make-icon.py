#!/usr/bin/env python3
"""アプリアイコンを生成する。黒背景に、文字盤のコンプリケーションと同じ「2行のタスク」。

  python3 Tools/make-icon.py            watch 版（既定。Apple Watch の輪郭の中に2行）
  python3 Tools/make-icon.py text       text 版（黒地に2行だけ）
  python3 Tools/make-icon.py bars       bars 版（円＋バー）

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

def render_watch():
    """Apple Watch の輪郭の中に、文字盤のコンプリケーションを描く。"""
    BG = (255, 255, 255)
    BAND = (70, 70, 74)
    CASE = (52, 52, 56)
    EDGE = (120, 120, 124)
    img = Image.new("RGB", (SIZE, SIZE), BG)
    d = ImageDraw.Draw(img)

    # バンド（上下に少しだけ見せる）
    d.rounded_rectangle([340, 60, 684, 964], radius=40, fill=BAND)
    # ケース
    d.rounded_rectangle([250, 178, 774, 846], radius=130, fill=CASE, outline=EDGE, width=6)
    # デジタルクラウンとサイドボタン
    d.rounded_rectangle([774, 330, 812, 440], radius=14, fill=EDGE)
    d.rounded_rectangle([774, 480, 802, 620], radius=10, fill=CASE, outline=EDGE, width=4)
    # 画面
    sx0, sy0, sx1, sy1 = 288, 216, 736, 808
    d.rounded_rectangle([sx0, sy0, sx1, sy1], radius=100, fill=BLACK)

    # 画面内: 右上に時刻、その下にタスク2行
    d.text((sx1 - 44, sy0 + 44), "10:09", font=ImageFont.truetype(FONT, 60),
           fill=WHITE, anchor="rt", stroke_width=2, stroke_fill=WHITE)
    # 2行とも同じ基準サイズ。1行目が収まる最大サイズを求め、2行目はその 85%。
    pad = 30
    rows = [(470, WHITE, "洗濯する", 1.0), (640, GRAY, "電話する", 0.85)]
    r0 = 26
    x0 = sx0 + pad + r0 * 2 + 22
    size = 120
    while size > 30:
        font = ImageFont.truetype(FONT, size)
        if d.textlength(rows[0][2], font=font) <= sx1 - pad - x0: break
        size -= 3
    for cy, color, label, scale in rows:
        r = int(r0 * scale)
        circle(d, sx0 + pad + r0, cy, r, color, int(10 * scale))
        font = ImageFont.truetype(FONT, int(size * scale))
        d.text((x0, cy), label, font=font, fill=color, anchor="lm",
               stroke_width=max(2, int(size * scale) // 25), stroke_fill=color)
    return img

def render(variant):
    if variant == "watch":
        return render_watch()
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
    variant = sys.argv[1] if len(sys.argv) > 1 else "watch"
    img = render(variant)
    write_asset(img, os.path.join(ROOT, "iOS", "Assets.xcassets"), "ios")
    write_asset(img, os.path.join(ROOT, "Watch", "Assets.xcassets"), "watchos")
    img.save(os.path.join(ROOT, "Tools", f"icon-preview-{variant}.png"))
    print(f"icon ({variant}) written")
