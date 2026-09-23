// アプリアイコンを描く。1024x1024 の PNG を作る。
//   swift tools/make-icon.swift <出力先.png>
//
// 1.1 の図柄：文字盤（曜日・日付・時刻・横長スロットに2行）を、角丸の縁で囲んだもの。
// **竜頭・側面ボタン・バンドは描かない。**
// 1.0 (2) は「アイコンが Apple Watch に似ている」で 5.2.5 却下された（引き継ぎ書 4-115）。
// この図柄はそこから竜頭とバンドを外しただけの「ギリギリ」を本人判断で攻めている。
// 却下されたら store/icon-candidates/ の控え（06 丸い腕時計 / 03 目盛り＋リスト）に替える。
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
// 行の描き方: ja（日本語の文字・1.2 まで）/ en（英語の文字）/ bars（文字なしの棒）
// 175か国で配信しているので、bars なら言語に依存しない
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "ja"
let S: CGFloat = 1024
func gray(_ g: CGFloat) -> CGColor { CGColor(gray: g, alpha: 1) }
let red = CGColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
NSGraphicsContext.saveGraphicsState()
cg.translateBy(x: 0, y: S); cg.scaleBy(x: 1, y: -1)                 // 上が y=0
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

func rrect(_ r: CGRect, _ radius: CGFloat, fill: CGColor? = nil, stroke: CGColor? = nil, lw: CGFloat = 0) {
    let p = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if let f = fill { cg.setFillColor(f); cg.addPath(p); cg.fillPath() }
    if let s = stroke { cg.setStrokeColor(s); cg.setLineWidth(lw); cg.addPath(p); cg.strokePath() }
}
func font(_ size: CGFloat, _ w: NSFont.Weight, rounded: Bool = false) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: w)
    if rounded, let d = f.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size) ?? f }
    return f
}
func text(_ s: String, _ f: NSFont, _ color: CGColor, left: CGPoint? = nil, right: CGPoint? = nil) {
    let str = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: NSColor(cgColor: color)!])
    let b = str.size()
    let p = left.map { CGPoint(x: $0.x, y: $0.y - b.height / 2) } ?? CGPoint(x: right!.x - b.width, y: right!.y - b.height / 2)
    str.draw(at: p)
}

// 背景（上がわずかに明るい炭色）
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [gray(0.15), gray(0.02)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: S), options: [])

// 画面と縁。watchOS は円に切り抜かれるので、角が半径 512 の円に収まる大きさにしてある
rrect(CGRect(x: 162, y: 112, width: 700, height: 800), 170, fill: gray(0), stroke: gray(0.28), lw: 26)

// 上下の余白をそろえる（画面の内側 125〜899 に対して、上下ともおよそ 120）
let L: CGFloat = 238, R: CGFloat = 786
text("SUN", font(58, .semibold), red, left: CGPoint(x: L, y: 276))
text("13", font(96, .semibold, rounded: true), gray(1), left: CGPoint(x: L, y: 346))
text("10:09", font(132, .medium, rounded: true), gray(1), right: CGPoint(x: R, y: 312))   // 日付とくっつかない大きさ

let slot = CGRect(x: L, y: 460, width: R - L, height: 320)
rrect(slot, 54, fill: gray(0.16))
switch mode {
case "bars":
    // 文字の代わりに角丸の棒2本。1行目は幅いっぱい、2行目は短く
    rrect(CGRect(x: L + 42, y: 560 - 34, width: (R - L) - 130, height: 68), 34, fill: red)
    rrect(CGRect(x: L + 42, y: 690 - 34, width: ((R - L) - 130) * 0.62, height: 68), 34, fill: red)
case "en":
    text("Do laundry", font(96, .bold), red, left: CGPoint(x: L + 42, y: 560))
    text("Call Mom", font(96, .bold), red, left: CGPoint(x: L + 42, y: 690))
default:
    text("洗濯する", font(104, .bold), red, left: CGPoint(x: L + 42, y: 560))
    text("電話する", font(104, .bold), red, left: CGPoint(x: L + 42, y: 690))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
